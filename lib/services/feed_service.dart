import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/services/firebase_error_handler.dart';
import 'package:flutter_chat_app/services/cloudinary_service.dart';

class FeedService {
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

  // Get all posts for the feed with error handling
  Stream<List<Post>> getPosts({BuildContext? context}) {
    try {
      // Create a stream transformer to handle errors
      StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>> errorHandler =
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>>.fromHandlers(
        handleError: (error, stackTrace, sink) async {
          print('❌ Error in getPosts stream: $error');

          // Try to recover from the error
          bool recovered =
              await _errorHandler.handleFirebaseException(error, context);

          if (recovered) {
            // If recovery was successful, notify about error but don't break the stream
            // Return an empty list via the error controller instead of trying to create a fake QuerySnapshot
            _errorController.add(
                "Feed data temporarily unavailable. Attempting to reconnect...");

            // We won't add anything to the sink, which will effectively pause the stream
            // The UI will show the previous valid state or loading indicator
          } else {
            // If recovery failed, propagate the error
            _errorController
                .add("Unable to load feed. Please try again later.");
            sink.addError(error, stackTrace);
          }
        },
      );

      return _firestore
          .collection('posts')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .transform(errorHandler) // Apply the error handler
          .map((snapshot) {
        try {
          return snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();
        } catch (e) {
          print('❌ Error parsing posts: $e');
          _errorController.add("Error loading posts. Data might be corrupted.");
          return <Post>[];
        }
      });
    } catch (e) {
      print('❌ Fatal error setting up posts stream: $e');
      _errorController
          .add("Critical error in feed service. Please restart the app.");

      // Return an empty stream to avoid breaking the UI
      return Stream.value(<Post>[]);
    }
  }

  // Get posts for a specific user with error handling
  Stream<List<Post>> getUserPosts(String userId, {BuildContext? context}) {
    try {
      // Create a stream transformer to handle errors
      StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>> errorHandler =
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>>.fromHandlers(
        handleError: (error, stackTrace, sink) async {
          print('❌ Error in getUserPosts stream: $error');

          // Try to recover from the error
          bool recovered =
              await _errorHandler.handleFirebaseException(error, context);

          if (recovered) {
            // If recovery was successful, notify about error but don't break the stream
            _errorController.add(
                "User posts temporarily unavailable. Attempting to reconnect...");

            // We won't add anything to the sink, which will effectively pause the stream
            // The UI will show the previous valid state or loading indicator
          } else {
            // If recovery failed, propagate the error
            _errorController
                .add("Unable to load user posts. Please try again later.");
            sink.addError(error, stackTrace);
          }
        },
      );

      return _firestore
          .collection('posts')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .snapshots()
          .transform(errorHandler) // Apply the error handler
          .map((snapshot) {
        try {
          return snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();
        } catch (e) {
          print('❌ Error parsing user posts: $e');
          _errorController
              .add("Error loading user posts. Data might be corrupted.");
          return <Post>[];
        }
      });
    } catch (e) {
      print('❌ Fatal error setting up user posts stream: $e');
      _errorController
          .add("Critical error in user feed service. Please restart the app.");

      // Return an empty stream to avoid breaking the UI
      return Stream.value(<Post>[]);
    }
  }

  // Like or unlike a post with error handling
  Future<void> toggleLike(String postId, {BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      DocumentReference postRef = _firestore.collection('posts').doc(postId);

      return _firestore.runTransaction((transaction) async {
        DocumentSnapshot postSnapshot = await transaction.get(postRef);

        if (!postSnapshot.exists) {
          throw Exception("Post does not exist!");
        }

        List<String> likes = List<String>.from(
            (postSnapshot.data() as Map<String, dynamic>)['likes'] ?? []);

        if (likes.contains(currentUserId)) {
          // Unlike
          likes.remove(currentUserId);
        } else {
          // Like
          likes.add(currentUserId!);
        }

        transaction.update(postRef, {'likes': likes});
      });
    } catch (e) {
      print('❌ Error toggling like: $e');
      _errorController.add("Couldn't update like status. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Add a new post with error handling
  Future<void> addPost({
    required String caption,
    required String imageUrl,
    String location = '',
    BuildContext? context,
  }) async {
    if (currentUserId == null) return;

    try {
      // Get user data for the post
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUserId).get();

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      Post post = Post(
        id: '', // Will be set by Firestore
        userId: currentUserId!,
        username: userData['username'] ?? 'Anonymous',
        userProfileImage: userData['profileImageUrl'] ?? '',
        caption: caption,
        imageUrl: imageUrl,
        timestamp: DateTime.now(),
        likes: [],
        commentsCount: 0,
        location: location,
      );

      await _firestore.collection('posts').add(post.toMap());
    } catch (e) {
      print('❌ Error adding post: $e');
      _errorController.add("Couldn't create post. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Delete a post with error handling
  Future<void> deletePost(String postId, {BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      // Check if the post belongs to current user
      DocumentSnapshot postDoc =
          await _firestore.collection('posts').doc(postId).get();

      if (!postDoc.exists) return;

      Map<String, dynamic> postData = postDoc.data() as Map<String, dynamic>;

      if (postData['userId'] != currentUserId) {
        throw Exception("You don't have permission to delete this post");
      }

      await _firestore.collection('posts').doc(postId).delete();
    } catch (e) {
      print('❌ Error deleting post: $e');
      _errorController.add("Couldn't delete post. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Add a comment to a post with error handling
  Future<void> addComment(String postId, String comment,
      {BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      // Get user data for the comment
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUserId).get();

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Add comment to comments subcollection
      await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .add({
        'userId': currentUserId,
        'username': userData['username'] ?? 'Anonymous',
        'userProfileImage': userData['profileImageUrl'] ?? '',
        'text': comment,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update comment count
      await _firestore.collection('posts').doc(postId).update({
        'commentsCount': FieldValue.increment(1),
      });
    } catch (e) {
      print('❌ Error adding comment: $e');
      _errorController.add("Couldn't add comment. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }

  // Get comments for a post with error handling
  Stream<List<Map<String, dynamic>>> getComments(String postId,
      {BuildContext? context}) {
    try {
      // Create a stream transformer to handle errors
      StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>> errorHandler =
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>>.fromHandlers(
        handleError: (error, stackTrace, sink) async {
          print('❌ Error in getComments stream: $error');

          // Try to recover from the error
          bool recovered =
              await _errorHandler.handleFirebaseException(error, context);

          if (recovered) {
            // If recovery was successful, notify about error but don't break the stream
            _errorController.add(
                "Comments temporarily unavailable. Attempting to reconnect...");
          } else {
            // If recovery failed, propagate the error
            _errorController
                .add("Unable to load comments. Please try again later.");
            sink.addError(error, stackTrace);
          }
        },
      );

      return _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .orderBy('timestamp', descending: false)
          .snapshots()
          .transform(errorHandler) // Apply the error handler
          .map((snapshot) {
        try {
          return snapshot.docs.map((doc) {
            var data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        } catch (e) {
          print('❌ Error parsing comments: $e');
          _errorController
              .add("Error loading comments. Data might be corrupted.");
          return <Map<String, dynamic>>[];
        }
      });
    } catch (e) {
      print('❌ Fatal error setting up comments stream: $e');
      _errorController
          .add("Critical error in comments service. Please try again.");

      // Return an empty stream to avoid breaking the UI
      return Stream.value(<Map<String, dynamic>>[]);
    }
  }

  // Clean up resources when no longer needed
  void dispose() {
    _errorController.close();
  }

  // Check if the user has created any posts yet
  Future<bool> hasUserCreatedPosts({BuildContext? context}) async {
    if (currentUserId == null) return false;

    try {
      // Check if the current user has any posts
      final userPostsSnapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: currentUserId)
          .limit(1)
          .get();

      return userPostsSnapshot.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking user posts: $e');
      _errorController.add("Couldn't check user posts. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      return false;
    }
  }

  // Initialize posts collection for the current user
  Future<void> initializePostsCollection({BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      // Check if user has created any posts
      bool hasExistingPosts = await hasUserCreatedPosts(context: context);

      if (!hasExistingPosts) {
        // Just check the user posts collection, no need to create a demo post
        print('📝 Initializing posts collection for user: $currentUserId');
      }
    } catch (e) {
      print('❌ Error initializing posts collection: $e');
      _errorController.add("Couldn't initialize posts. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
    }
  }

  // No longer creates a sample post but checks if user has posts
  Future<void> checkUserPostsCollection({BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      // Check if user has created any posts
      bool hasExistingPosts = await hasUserCreatedPosts(context: context);

      if (!hasExistingPosts) {
        // User has no posts yet, but we don't create a demo post
        // Instead, we could show a UI hint to create a first post
        print('📝 User has no posts yet. They should create their first post!');
      }
    } catch (e) {
      print('❌ Error checking posts collection: $e');
      _errorController.add("Couldn't check posts. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
    }
  }

  // Pick image from camera or gallery and return XFile
  Future<XFile?> pickImageFromSource(ImageSource source,
      {BuildContext? context}) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      return pickedFile;
    } catch (e) {
      print('❌ Error picking image: $e');
      _errorController.add("Couldn't pick image. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      return null;
    }
  }

  // Process picked image and return the file and web image bytes
  Future<Map<String, dynamic>> processPickedImage(XFile? pickedFile) async {
    dynamic imageFile;
    Uint8List? webImage;

    if (pickedFile == null) {
      return {'imageFile': null, 'webImage': null};
    }

    try {
      if (kIsWeb) {
        // Handle web platform
        var bytes = await pickedFile.readAsBytes();
        webImage = bytes;
        imageFile = pickedFile;
      } else {
        // Handle mobile platforms
        imageFile = File(pickedFile.path);
      }

      return {
        'imageFile': imageFile,
        'webImage': webImage,
      };
    } catch (e) {
      print('❌ Error processing image: $e');
      return {'imageFile': null, 'webImage': null};
    }
  }

  // Upload image to Cloudinary and return the URL
  Future<String?> uploadFeedImage({
    required dynamic imageFile,
    Uint8List? webImage,
    BuildContext? context,
  }) async {
    if (imageFile == null) return null;

    try {
      // Add detailed logging
      print('🔄 Starting feed image upload process');

      // Upload the image to Cloudinary using our service
      String downloadUrl = await CloudinaryService.uploadImage(
        imageFile: imageFile,
        webImage: webImage,
        preset: CloudinaryService.feedPostPreset,
      );

      return downloadUrl;
    } catch (e) {
      print('❌ Error uploading feed image: $e');

      // Provide a more detailed error message based on the exception
      if (e.toString().contains('timed out')) {
        _errorController.add(
            "Upload timed out. Please check your internet connection and try again.");
      } else if (e.toString().contains('Failed to upload image')) {
        _errorController.add(
            "Image upload failed. Please try with a smaller image or check your network.");
      } else {
        _errorController
            .add("Couldn't upload image: ${e.toString().split(':').last}");
      }

      await _errorHandler.handleFirebaseException(e, context);
      return null;
    }
  }

  // Create a post with an image - full process
  Future<bool> createPostWithImage({
    required XFile? pickedImage,
    required String caption,
    String location = '',
    BuildContext? context,
  }) async {
    if (currentUserId == null) {
      _errorController.add("You must be logged in to create a post");
      return false;
    }

    if (pickedImage == null) {
      _errorController.add("No image selected for post");
      return false;
    }

    if (caption.trim().isEmpty) {
      _errorController.add("Caption cannot be empty");
      return false;
    }

    try {
      // Show loading indicator if context is provided
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Creating post...'),
              duration: Duration(seconds: 30)),
        );
      }

      // Process the picked image
      final processedImage = await processPickedImage(pickedImage);

      if (processedImage['imageFile'] == null) {
        _errorController.add("Couldn't process image. Please try again.");
        if (context != null) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
        return false;
      }

      // Try to upload the image to Cloudinary with retry mechanism
      String? imageUrl;
      int retryCount = 0;
      const maxRetries = 2;

      while (imageUrl == null && retryCount <= maxRetries) {
        try {
          imageUrl = await uploadFeedImage(
            imageFile: processedImage['imageFile'],
            webImage: processedImage['webImage'],
            context: context,
          );

          if (imageUrl == null && retryCount < maxRetries) {
            retryCount++;
            print('🔄 Retry attempt $retryCount for image upload');
            // Wait a bit before retrying
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

      if (imageUrl == null) {
        _errorController.add(
            "Failed to upload image after several attempts. Please try again with a smaller image.");
        if (context != null) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Image upload failed. Try using a smaller image or check your network.'),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      // Create the post with the image URL
      await addPost(
        caption: caption,
        imageUrl: imageUrl,
        location: location,
        context: context,
      );

      // Hide loading indicator and show success message
      if (context != null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Post created successfully!'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green),
        );
      }

      return true;
    } catch (e) {
      print('❌ Error creating post with image: $e');

      // Provide more detailed error messages based on the exception type
      String errorMessage = "Couldn't create post. Please try again.";

      if (e.toString().contains('network')) {
        errorMessage = "Network error. Please check your internet connection.";
      } else if (e.toString().contains('permission')) {
        errorMessage = "Permission denied. Please check app permissions.";
      } else if (e.toString().contains('storage') ||
          e.toString().contains('quota')) {
        errorMessage = "Storage error. Your image may be too large.";
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

  // Show a bottom sheet to choose between camera and gallery
  Future<XFile?> showImageSourceSheet(BuildContext context) async {
    XFile? pickedFile;

    await showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Photo Library'),
                onTap: () async {
                  Navigator.of(context).pop();
                  pickedFile = await pickImageFromSource(ImageSource.gallery,
                      context: context);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_camera),
                title: Text('Camera'),
                onTap: () async {
                  Navigator.of(context).pop();
                  pickedFile = await pickImageFromSource(ImageSource.camera,
                      context: context);
                },
              ),
            ],
          ),
        );
      },
    );

    return pickedFile;
  }

  // Get a single post by ID with real-time updates
  Stream<Post> getPostById(String postId, {BuildContext? context}) {
    try {
      // Create a stream transformer to handle errors
      StreamTransformer<DocumentSnapshot<Map<String, dynamic>>,
              DocumentSnapshot<Map<String, dynamic>>> errorHandler =
          StreamTransformer<DocumentSnapshot<Map<String, dynamic>>,
              DocumentSnapshot<Map<String, dynamic>>>.fromHandlers(
        handleError: (error, stackTrace, sink) async {
          print('❌ Error in getPostById stream: $error');

          // Try to recover from the error
          bool recovered =
              await _errorHandler.handleFirebaseException(error, context);

          if (recovered) {
            // If recovery was successful, notify about error but don't break the stream
            _errorController.add(
                "Post data temporarily unavailable. Attempting to reconnect...");
          } else {
            // If recovery failed, propagate the error
            _errorController
                .add("Unable to load post. Please try again later.");
            sink.addError(error, stackTrace);
          }
        },
      );

      return _firestore
          .collection('posts')
          .doc(postId)
          .snapshots()
          .transform(errorHandler) // Apply the error handler
          .map((snapshot) {
        try {
          if (!snapshot.exists) {
            throw Exception("Post does not exist!");
          }
          return Post.fromFirestore(snapshot);
        } catch (e) {
          print('❌ Error parsing post: $e');
          _errorController.add("Error loading post. Data might be corrupted.");
          throw e;
        }
      });
    } catch (e) {
      print('❌ Fatal error setting up post stream: $e');
      _errorController
          .add("Critical error loading post. Please try again later.");

      // Return an empty stream to avoid breaking the UI
      return Stream.error(e);
    }
  }
}
