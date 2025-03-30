import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_chat_app/models/story_model.dart';
import 'package:flutter_chat_app/services/firebase_error_handler.dart';
import 'package:flutter_chat_app/services/cloudinary_service.dart';

class StoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseErrorHandler _errorHandler = FirebaseErrorHandler();
  final ImagePicker _picker = ImagePicker();

  // Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  // Controller for error events
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // Stream of error messages that UI can listen to
  Stream<String> get onError => _errorController.stream;

  // Get all active stories for the feed (not expired)
  Stream<List<Story>> getActiveStories({BuildContext? context}) {
    try {
      // Create a stream transformer to handle errors
      StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>> errorHandler =
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>>.fromHandlers(
        handleError: (error, stackTrace, sink) async {
          print('❌ Error in getActiveStories stream: $error');

          // Try to recover from the error
          bool recovered =
              await _errorHandler.handleFirebaseException(error, context);

          if (recovered) {
            _errorController.add(
                "Stories temporarily unavailable. Attempting to reconnect...");
          } else {
            _errorController
                .add("Unable to load stories. Please try again later.");
            sink.addError(error, stackTrace);
          }
        },
      );

      // Get stories that haven't expired yet
      return _firestore
          .collection('stories')
          .where('expiryTime',
              isGreaterThan: Timestamp.fromDate(DateTime.now()))
          .orderBy('expiryTime', descending: false)
          .snapshots()
          .transform(errorHandler)
          .map((snapshot) {
        try {
          return snapshot.docs.map((doc) => Story.fromFirestore(doc)).toList();
        } catch (e) {
          print('❌ Error parsing stories: $e');
          _errorController
              .add("Error loading stories. Data might be corrupted.");
          return <Story>[];
        }
      });
    } catch (e) {
      print('❌ Fatal error setting up stories stream: $e');
      _errorController
          .add("Critical error in story service. Please restart the app.");
      return Stream.value(<Story>[]);
    }
  }

  // Get stories for a specific user
  Stream<List<Story>> getUserStories(String userId, {BuildContext? context}) {
    try {
      StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>> errorHandler =
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>>.fromHandlers(
        handleError: (error, stackTrace, sink) async {
          print('❌ Error in getUserStories stream: $error');

          bool recovered =
              await _errorHandler.handleFirebaseException(error, context);

          if (recovered) {
            _errorController.add(
                "User stories temporarily unavailable. Attempting to reconnect...");
          } else {
            _errorController
                .add("Unable to load user stories. Please try again later.");
            sink.addError(error, stackTrace);
          }
        },
      );

      return _firestore
          .collection('stories')
          .where('userId', isEqualTo: userId)
          .where('expiryTime',
              isGreaterThan: Timestamp.fromDate(DateTime.now()))
          .orderBy('expiryTime', descending: true)
          .snapshots()
          .transform(errorHandler)
          .map((snapshot) {
        try {
          return snapshot.docs.map((doc) => Story.fromFirestore(doc)).toList();
        } catch (e) {
          print('❌ Error parsing user stories: $e');
          _errorController
              .add("Error loading user stories. Data might be corrupted.");
          return <Story>[];
        }
      });
    } catch (e) {
      print('❌ Fatal error setting up user stories stream: $e');
      _errorController
          .add("Critical error in user story service. Please restart the app.");
      return Stream.value(<Story>[]);
    }
  }

  // Create a new story
  Future<void> addStory({
    required String mediaUrl,
    String caption = '',
    String background = '',
    String mediaType = 'image',
    BuildContext? context,
  }) async {
    if (currentUserId == null) return;

    try {
      // Get user data for the story
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUserId).get();
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Calculate expiry time (24 hours from now)
      DateTime expiryTime = DateTime.now().add(const Duration(hours: 24));

      Story story = Story(
        id: '', // Will be set by Firestore
        userId: currentUserId!,
        username: userData['username'] ?? 'Anonymous',
        userProfileImage: userData['profileImageUrl'] ?? '',
        mediaUrl: mediaUrl,
        timestamp: DateTime.now(),
        expiryTime: expiryTime,
        caption: caption,
        viewers: [],
        background: background,
        mediaType: mediaType,
        isHighlighted: false,
      );

      await _firestore.collection('stories').add(story.toMap());
    } catch (e) {
      print('❌ Error adding story: $e');
      _errorController.add("Couldn't create story. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Mark a story as viewed by the current user
  Future<void> markStoryAsViewed(String storyId,
      {BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      DocumentReference storyRef =
          _firestore.collection('stories').doc(storyId);

      return _firestore.runTransaction((transaction) async {
        DocumentSnapshot storySnapshot = await transaction.get(storyRef);

        if (!storySnapshot.exists) {
          throw Exception("Story does not exist!");
        }

        List<String> viewers = List<String>.from(
            (storySnapshot.data() as Map<String, dynamic>)['viewers'] ?? []);

        if (!viewers.contains(currentUserId)) {
          // Add current user to viewers list if not already there
          viewers.add(currentUserId!);
          transaction.update(storyRef, {'viewers': viewers});
        }
      });
    } catch (e) {
      print('❌ Error marking story as viewed: $e');
      await _errorHandler.handleFirebaseException(e, context);
    }
  }

  // Delete a story
  Future<void> deleteStory(String storyId, {BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      // Check if the story belongs to current user
      DocumentSnapshot storyDoc =
          await _firestore.collection('stories').doc(storyId).get();

      if (!storyDoc.exists) return;

      Map<String, dynamic> storyData = storyDoc.data() as Map<String, dynamic>;

      if (storyData['userId'] != currentUserId) {
        throw Exception("You don't have permission to delete this story");
      }

      await _firestore.collection('stories').doc(storyId).delete();
    } catch (e) {
      print('❌ Error deleting story: $e');
      _errorController.add("Couldn't delete story. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Add story to highlights
  Future<void> highlightStory(String storyId, bool highlight,
      {BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      // Check if the story belongs to current user
      DocumentSnapshot storyDoc =
          await _firestore.collection('stories').doc(storyId).get();

      if (!storyDoc.exists) return;

      Map<String, dynamic> storyData = storyDoc.data() as Map<String, dynamic>;

      if (storyData['userId'] != currentUserId) {
        throw Exception("You don't have permission to edit this story");
      }

      await _firestore.collection('stories').doc(storyId).update({
        'isHighlighted': highlight,
        // If highlighting, extend expiry time indefinitely (1 year)
        if (highlight)
          'expiryTime':
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 365))),
      });
    } catch (e) {
      print('❌ Error updating story highlight status: $e');
      _errorController.add("Couldn't update story. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Get highlighted stories for a user
  Stream<List<Story>> getUserHighlights(String userId,
      {BuildContext? context}) {
    try {
      StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>> errorHandler =
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>>.fromHandlers(
        handleError: (error, stackTrace, sink) async {
          print('❌ Error in getUserHighlights stream: $error');

          bool recovered =
              await _errorHandler.handleFirebaseException(error, context);

          if (recovered) {
            _errorController.add(
                "User highlights temporarily unavailable. Attempting to reconnect...");
          } else {
            _errorController
                .add("Unable to load user highlights. Please try again later.");
            sink.addError(error, stackTrace);
          }
        },
      );

      return _firestore
          .collection('stories')
          .where('userId', isEqualTo: userId)
          .where('isHighlighted', isEqualTo: true)
          .orderBy('timestamp', descending: true)
          .snapshots()
          .transform(errorHandler)
          .map((snapshot) {
        try {
          return snapshot.docs.map((doc) => Story.fromFirestore(doc)).toList();
        } catch (e) {
          print('❌ Error parsing user highlights: $e');
          _errorController
              .add("Error loading user highlights. Data might be corrupted.");
          return <Story>[];
        }
      });
    } catch (e) {
      print('❌ Fatal error setting up user highlights stream: $e');
      _errorController.add(
          "Critical error in user highlights service. Please restart the app.");
      return Stream.value(<Story>[]);
    }
  }

  // Group stories by user for feed display
  Map<String, List<Story>> groupStoriesByUser(List<Story> stories) {
    Map<String, List<Story>> groupedStories = {};

    for (var story in stories) {
      if (!groupedStories.containsKey(story.userId)) {
        groupedStories[story.userId] = [];
      }
      groupedStories[story.userId]!.add(story);
    }

    return groupedStories;
  }

  // Pick image from camera or gallery for a story
  Future<XFile?> pickStoryMedia(ImageSource source,
      {BuildContext? context}) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85, // Use slightly higher quality for stories
      );
      return pickedFile;
    } catch (e) {
      print('❌ Error picking story media: $e');
      _errorController.add("Couldn't pick media. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      return null;
    }
  }

  // Process picked image and return the file and web image bytes
  Future<Map<String, dynamic>> processPickedStoryMedia(
      XFile? pickedFile) async {
    dynamic mediaFile;
    Uint8List? webImage;

    if (pickedFile == null) {
      return {'mediaFile': null, 'webImage': null};
    }

    try {
      if (kIsWeb) {
        // Handle web platform
        var bytes = await pickedFile.readAsBytes();
        webImage = bytes;
        mediaFile = pickedFile;
      } else {
        // Handle mobile platforms
        mediaFile = File(pickedFile.path);
      }

      return {
        'mediaFile': mediaFile,
        'webImage': webImage,
      };
    } catch (e) {
      print('❌ Error processing story media: $e');
      return {'mediaFile': null, 'webImage': null};
    }
  }

  // Upload story media to Cloudinary and return the URL
  Future<String?> uploadStoryMedia({
    required dynamic mediaFile,
    Uint8List? webImage,
    BuildContext? context,
  }) async {
    if (mediaFile == null) return null;

    try {
      print('🔄 Starting story media upload process');

      // Upload the image to Cloudinary using our service
      String downloadUrl = await CloudinaryService.uploadImage(
        imageFile: mediaFile,
        webImage: webImage,
        preset:
            CloudinaryService.storyMediaPreset, // Assuming this preset exists
      );

      return downloadUrl;
    } catch (e) {
      print('❌ Error uploading story media: $e');

      // Provide a detailed error message
      if (e.toString().contains('timed out')) {
        _errorController.add(
            "Upload timed out. Please check your internet connection and try again.");
      } else if (e.toString().contains('Failed to upload')) {
        _errorController.add(
            "Media upload failed. Please try with a smaller media file or check your network.");
      } else {
        _errorController
            .add("Couldn't upload media: ${e.toString().split(':').last}");
      }

      await _errorHandler.handleFirebaseException(e, context);
      return null;
    }
  }

  // Create a story with media - full process
  Future<bool> createStoryWithMedia({
    required XFile? pickedMedia,
    String caption = '',
    String background = '',
    String mediaType = 'image',
    BuildContext? context,
  }) async {
    if (currentUserId == null) {
      _errorController.add("You must be logged in to create a story");
      return false;
    }

    if (pickedMedia == null && mediaType != 'text') {
      _errorController.add("No media selected for story");
      return false;
    }

    // For text stories, background is required
    if (mediaType == 'text' && background.isEmpty && caption.isEmpty) {
      _errorController
          .add("Text stories require either a caption or background");
      return false;
    }

    try {
      // Show loading indicator if context is provided
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Creating story...'),
            duration: Duration(seconds: 30),
          ),
        );
      }

      String? mediaUrl;

      // Only process and upload media if it's not a text-only story
      if (mediaType != 'text') {
        // Process the picked media
        final processedMedia = await processPickedStoryMedia(pickedMedia);

        if (processedMedia['mediaFile'] == null) {
          _errorController.add("Couldn't process media. Please try again.");
          if (context != null) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
          return false;
        }

        // Try to upload the media
        int retryCount = 0;
        const maxRetries = 2;

        while (mediaUrl == null && retryCount <= maxRetries) {
          try {
            mediaUrl = await uploadStoryMedia(
              mediaFile: processedMedia['mediaFile'],
              webImage: processedMedia['webImage'],
              context: context,
            );

            if (mediaUrl == null && retryCount < maxRetries) {
              retryCount++;
              print('🔄 Retry attempt $retryCount for media upload');
              await Future.delayed(Duration(seconds: 2));
            }
          } catch (e) {
            print('❌ Upload attempt $retryCount failed: $e');
            if (retryCount < maxRetries) {
              retryCount++;
              await Future.delayed(Duration(seconds: 2));
            } else {
              rethrow;
            }
          }
        }

        if (mediaUrl == null) {
          _errorController.add(
              "Failed to upload media after several attempts. Please try again with a smaller file.");
          if (context != null) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Media upload failed. Try using a smaller file or check your network.'),
                duration: Duration(seconds: 4),
                backgroundColor: Colors.red,
              ),
            );
          }
          return false;
        }
      }

      // Create the story
      await addStory(
        mediaUrl: mediaUrl ?? '', // Empty for text-only stories
        caption: caption,
        background: background,
        mediaType: mediaType,
        context: context,
      );

      // Hide loading indicator and show success message
      if (context != null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Story created successfully!'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }

      return true;
    } catch (e) {
      print('❌ Error creating story with media: $e');

      // Provide detailed error messages
      String errorMessage = "Couldn't create story. Please try again.";

      if (e.toString().contains('network')) {
        errorMessage = "Network error. Please check your internet connection.";
      } else if (e.toString().contains('permission')) {
        errorMessage = "Permission denied. Please check app permissions.";
      } else if (e.toString().contains('storage') ||
          e.toString().contains('quota')) {
        errorMessage = "Storage error. Your media may be too large.";
      }

      _errorController.add(errorMessage);

      // Hide loading indicator and show error
      if (context != null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.red,
          ),
        );
      }

      await _errorHandler.handleFirebaseException(e, context);
      return false;
    }
  }

  // Clean up resources when no longer needed
  void dispose() {
    _errorController.close();
  }

  // Initialize the stories collection
  Future<void> initializeStoriesCollection({BuildContext? context}) async {
    try {
      // Attempt to access the collection to ensure it exists
      print('🔍 Initializing Stories collection...');

      // Check if the stories collection exists by making a small query
      await _firestore.collection('stories').limit(1).get();

      print('✅ Stories collection initialized successfully');
    } catch (e) {
      print('❌ Error initializing stories collection: $e');

      // Try to handle any Firebase errors
      await _errorHandler.handleFirebaseException(e, context);

      // Even if there's an error, don't rethrow as the collection will be created when needed
    }
  }
}
