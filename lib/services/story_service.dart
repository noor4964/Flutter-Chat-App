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
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

class StoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseErrorHandler _errorHandler = FirebaseErrorHandler();
  final ImagePicker _picker = ImagePicker();

  // Available filters for stories
  static const Map<String, Map<String, dynamic>> filters = {
    'none': {'name': 'Normal', 'description': 'No filter'},
    'vintage': {'name': 'Vintage', 'description': 'Old school classic look'},
    'monochrome': {'name': 'Monochrome', 'description': 'Black and white'},
    'sepia': {'name': 'Sepia', 'description': 'Warm brown tones'},
    'vivid': {'name': 'Vivid', 'description': 'Enhanced colors and contrast'},
    'dramatic': {'name': 'Dramatic', 'description': 'High contrast moody look'},
    'cool': {'name': 'Cool', 'description': 'Blue toned filter'},
    'warm': {'name': 'Warm', 'description': 'Golden warm tones'},
  };

  // Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  // Controller for error events
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // Stream of error messages that UI can listen to
  Stream<String> get onError => _errorController.stream;

  // Helper method to check friendship status between two users
  Future<bool> _checkFriendshipStatus(String userId1, String userId2) async {
    if (userId1.isEmpty || userId2.isEmpty || userId1 == userId2) {
      return userId1 == userId2; // Users can always see their own stories
    }

    try {
      final connectionsSnapshot = await _firestore
          .collection('connections')
          .where('status', isEqualTo: 'accepted')
          .where(Filter.or(
              Filter.and(Filter('senderId', isEqualTo: userId1),
                  Filter('receiverId', isEqualTo: userId2)),
              Filter.and(Filter('senderId', isEqualTo: userId2),
                  Filter('receiverId', isEqualTo: userId1))))
          .get();

      return connectionsSnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking friendship status: $e');
      return false;
    }
  }

  // Get list of current user's friends
  Future<List<String>> _getCurrentUserFriends() async {
    if (currentUserId == null) return [];

    try {
      final connectionsSnapshot = await _firestore
          .collection('connections')
          .where('status', isEqualTo: 'accepted')
          .where(Filter.or(
              Filter('senderId', isEqualTo: currentUserId!),
              Filter('receiverId', isEqualTo: currentUserId!)))
          .get();

      List<String> friendIds = [];
      for (var doc in connectionsSnapshot.docs) {
        final data = doc.data();
        final String friendId = data['senderId'] == currentUserId
            ? data['receiverId']
            : data['senderId'];
        friendIds.add(friendId);
      }

      // Add current user to see own stories
      friendIds.add(currentUserId!);
      return friendIds;
    } catch (e) {
      print('Error getting user friends: $e');
      return [currentUserId!]; // At least include current user
    }
  }

  // Get all active stories for the feed (friends-only)
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
          .asyncMap((snapshot) async {
        try {
          List<Story> allStories = snapshot.docs.map((doc) => Story.fromFirestore(doc)).toList();
          
          // Get current user's friends list
          List<String> friendIds = await _getCurrentUserFriends();
          
          // Filter stories based on privacy and friendship
          List<Story> visibleStories = [];
          for (Story story in allStories) {
            // Always show public stories
            if (story.privacy == StoryPrivacy.public) {
              visibleStories.add(story);
            }
            // Show friends-only stories if user is friends with story creator
            else if (story.privacy == StoryPrivacy.friends && 
                     friendIds.contains(story.userId)) {
              visibleStories.add(story);
            }
            // Private stories are only visible to the creator (handled by friendIds containing current user)
            else if (story.privacy == StoryPrivacy.private && 
                     story.userId == currentUserId) {
              visibleStories.add(story);
            }
          }
          
          return visibleStories;
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

  // Get stories from users the current user follows
  Stream<List<Story>> getFollowedUsersStories({BuildContext? context}) async* {
    if (currentUserId == null) {
      yield [];
      return;
    }

    try {
      // Get the list of users the current user follows
      final followingDoc = await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('following')
          .get();

      final List<String> followingIds =
          followingDoc.docs.map((doc) => doc.id).toList();

      // Add current user to see their own stories
      followingIds.add(currentUserId!);

      if (followingIds.isEmpty) {
        yield [];
        return;
      }

      // Get stories from followed users
      yield* _firestore
          .collection('stories')
          .where('userId', whereIn: followingIds)
          .where('expiryTime',
              isGreaterThan: Timestamp.fromDate(DateTime.now()))
          .orderBy('expiryTime', descending: false)
          .snapshots()
          .map((snapshot) {
        try {
          return snapshot.docs.map((doc) => Story.fromFirestore(doc)).toList();
        } catch (e) {
          print('❌ Error parsing followed users stories: $e');
          return <Story>[];
        }
      });
    } catch (e) {
      print('❌ Error getting followed users stories: $e');
      yield [];
    }
  }

  // Get stories for a specific user (respecting privacy)
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
          .asyncMap((snapshot) async {
        try {
          List<Story> allStories = snapshot.docs.map((doc) => Story.fromFirestore(doc)).toList();
          
          // If viewing own stories, show all
          if (userId == currentUserId) {
            return allStories;
          }
          
          // Check friendship status
          bool isFriend = await _checkFriendshipStatus(currentUserId ?? '', userId);
          
          // Filter stories based on privacy and friendship
          List<Story> visibleStories = [];
          for (Story story in allStories) {
            // Always show public stories
            if (story.privacy == StoryPrivacy.public) {
              visibleStories.add(story);
            }
            // Show friends-only stories if user is friends with story creator
            else if (story.privacy == StoryPrivacy.friends && isFriend) {
              visibleStories.add(story);
            }
            // Private stories are never visible to others
          }
          
          return visibleStories;
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

  // Get user stories as a Future instead of Stream (useful for one-time checks)
  Future<List<Story>> getUserStoriesFuture(String userId,
      {BuildContext? context}) async {
    try {
      final snapshot = await _firestore
          .collection('stories')
          .where('userId', isEqualTo: userId)
          .where('expiryTime',
              isGreaterThan: Timestamp.fromDate(DateTime.now()))
          .orderBy('expiryTime', descending: true)
          .get();

      List<Story> allStories = snapshot.docs.map((doc) => Story.fromFirestore(doc)).toList();
      
      // If viewing own stories, show all
      if (userId == currentUserId) {
        return allStories;
      }
      
      // Check friendship status
      bool isFriend = await _checkFriendshipStatus(currentUserId ?? '', userId);
      
      // Filter stories based on privacy and friendship
      List<Story> visibleStories = [];
      for (Story story in allStories) {
        // Always show public stories
        if (story.privacy == StoryPrivacy.public) {
          visibleStories.add(story);
        }
        // Show friends-only stories if user is friends with story creator
        else if (story.privacy == StoryPrivacy.friends && isFriend) {
          visibleStories.add(story);
        }
        // Private stories are never visible to others
      }
      
      return visibleStories;
    } catch (e) {
      print('❌ Error getting user stories future: $e');
      await _errorHandler.handleFirebaseException(e, context);
      return [];
    }
  }

  // Create a new story with advanced options
  Future<void> addStory({
    required String mediaUrl,
    String caption = '',
    String background = '',
    String mediaType = 'image',
    Map<String, dynamic>? musicInfo,
    List<String> mentions = const [],
    String? location,
    String? filter,
    bool allowSharing = true,
    StoryPrivacy privacy = StoryPrivacy.friends,
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
        musicInfo: musicInfo,
        mentions: mentions,
        location: location,
        filter: filter,
        reactions: [],
        allowSharing: allowSharing,
        replies: [],
        privacy: privacy,
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

  // React to a story with an emoji
  Future<void> reactToStory(String storyId, String emoji,
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

        final storyData = storySnapshot.data() as Map<String, dynamic>;
        List<Map<String, dynamic>> reactions =
            List<Map<String, dynamic>>.from(storyData['reactions'] ?? []);

        // Check if the user has already reacted with this emoji
        final existingReactionIndex = reactions.indexWhere((reaction) =>
            reaction['userId'] == currentUserId && reaction['emoji'] == emoji);

        if (existingReactionIndex != -1) {
          // User already reacted with this emoji, remove it
          reactions.removeAt(existingReactionIndex);
        } else {
          // Add new reaction
          reactions.add({
            'userId': currentUserId,
            'emoji': emoji,
            'timestamp': Timestamp.now(),
          });
        }

        transaction.update(storyRef, {'reactions': reactions});
      });
    } catch (e) {
      print('❌ Error reacting to story: $e');
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Add a reply to a story
  Future<void> replyToStory(String storyId, String reply,
      {BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUserId).get();

      if (!userDoc.exists) {
        throw Exception("User not found");
      }

      final userData = userDoc.data() as Map<String, dynamic>;

      DocumentReference storyRef =
          _firestore.collection('stories').doc(storyId);

      return _firestore.runTransaction((transaction) async {
        DocumentSnapshot storySnapshot = await transaction.get(storyRef);

        if (!storySnapshot.exists) {
          throw Exception("Story does not exist!");
        }

        final storyData = storySnapshot.data() as Map<String, dynamic>;
        List<Map<String, dynamic>> replies =
            List<Map<String, dynamic>>.from(storyData['replies'] ?? []);

        // Add new reply
        replies.add({
          'userId': currentUserId,
          'username': userData['username'] ?? 'Anonymous',
          'profileImageUrl': userData['profileImageUrl'] ?? '',
          'reply': reply,
          'timestamp': Timestamp.now(),
        });

        transaction.update(storyRef, {'replies': replies});
      });
    } catch (e) {
      print('❌ Error replying to story: $e');
      _errorController.add("Couldn't add reply. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
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

  // Add users to mention list in a story
  Future<void> addMentions(String storyId, List<String> newMentions,
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

      // Get current mentions and add new ones (avoiding duplicates)
      List<String> currentMentions =
          List<String>.from(storyData['mentions'] ?? []);
      Set<String> updatedMentions = {...currentMentions, ...newMentions};

      await _firestore.collection('stories').doc(storyId).update({
        'mentions': updatedMentions.toList(),
      });
    } catch (e) {
      print('❌ Error adding mentions to story: $e');
      _errorController.add("Couldn't update mentions. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Add or update music info to a story
  Future<void> updateStoryMusic(String storyId, Map<String, dynamic> musicInfo,
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
        'musicInfo': musicInfo,
      });
    } catch (e) {
      print('❌ Error updating story music: $e');
      _errorController.add("Couldn't update music. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Change story sharing permissions
  Future<void> updateSharingPermission(String storyId, bool allowSharing,
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
        'allowSharing': allowSharing,
      });
    } catch (e) {
      print('❌ Error updating story sharing permissions: $e');
      _errorController
          .add("Couldn't update sharing permissions. Please try again.");
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

  // Pick video from camera or gallery
  Future<XFile?> pickStoryVideo(ImageSource source,
      {BuildContext? context}) async {
    try {
      final XFile? pickedVideo = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 30), // Limit video length
      );
      return pickedVideo;
    } catch (e) {
      print('❌ Error picking story video: $e');
      _errorController.add("Couldn't pick video. Please try again.");
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

  // Apply a filter to an image
  Future<File?> applyFilterToImage(File imageFile, String filterName,
      {BuildContext? context}) async {
    // This is a placeholder for filter implementation
    // In a real implementation, you would use image processing libraries
    try {
      // For now, we'll just return the original file since we don't have image processing
      // In a real app, this would apply specific filter effects using packages like image or photofilters
      return imageFile;
    } catch (e) {
      print('❌ Error applying filter: $e');
      _errorController.add("Couldn't apply filter. Please try again.");
      return null;
    }
  }

  // Upload story media to Cloudinary and return the URL
  Future<String?> uploadStoryMedia({
    required dynamic mediaFile,
    Uint8List? webImage,
    String? filterName,
    BuildContext? context,
  }) async {
    if (mediaFile == null) return null;

    try {
      print('🔄 Starting story media upload process');

      // Apply filter if specified and not on web
      if (filterName != null &&
          filterName != 'none' &&
          !kIsWeb &&
          mediaFile is File) {
        File? filteredFile =
            await applyFilterToImage(mediaFile, filterName, context: context);
        if (filteredFile != null) {
          mediaFile = filteredFile;
        }
      }

      // Upload the image to Cloudinary using our service
      String downloadUrl = await CloudinaryService.uploadImage(
        imageFile: mediaFile,
        webImage: webImage,
        preset: CloudinaryService.storyMediaPreset,
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

  // Create a story with media - full process with advanced options
  Future<bool> createStoryWithMedia({
    required XFile? pickedMedia,
    String caption = '',
    String background = '',
    String mediaType = 'image',
    Map<String, dynamic>? musicInfo,
    List<String> mentions = const [],
    String? location,
    String? filter,
    bool allowSharing = true,
    StoryPrivacy privacy = StoryPrivacy.friends,
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
              filterName: filter,
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

      // Create the story with all advanced options
      await addStory(
        mediaUrl: mediaUrl ?? '', // Empty for text-only stories
        caption: caption,
        background: background,
        mediaType: mediaType,
        musicInfo: musicInfo,
        mentions: mentions,
        location: location,
        filter: filter,
        allowSharing: allowSharing,
        privacy: privacy,
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

  // Get stories containing a specific hashtag
  Future<List<Story>> getStoriesByHashtag(String hashtag,
      {BuildContext? context}) async {
    try {
      // Normalize the hashtag by removing # if present and converting to lowercase
      hashtag = hashtag.startsWith('#') ? hashtag.substring(1) : hashtag;
      hashtag = hashtag.toLowerCase();

      // Query for stories with this hashtag in the caption
      final snapshot = await _firestore
          .collection('stories')
          .where('expiryTime',
              isGreaterThan: Timestamp.fromDate(DateTime.now()))
          .get();

      // Filter stories that contain the hashtag in caption
      return snapshot.docs
          .map((doc) => Story.fromFirestore(doc))
          .where((story) {
        final lowerCaption = story.caption.toLowerCase();
        return lowerCaption.contains('#$hashtag') ||
            lowerCaption.contains(' $hashtag ') ||
            lowerCaption.startsWith('$hashtag ') ||
            lowerCaption.endsWith(' $hashtag');
      }).toList();
    } catch (e) {
      print('❌ Error searching stories by hashtag: $e');
      await _errorHandler.handleFirebaseException(e, context);
      return [];
    }
  }
}
