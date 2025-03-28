import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/services/firebase_error_handler.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';

class FeedService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseErrorHandler _errorHandler = FirebaseErrorHandler();

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

  // A manual method to attempt recovery from Firestore errors
  Future<bool> attemptRecovery({BuildContext? context}) async {
    try {
      print('🔄 Manually attempting feed service recovery...');

      // First try to clear Firestore cache
      await FirebaseConfig.clearFirestoreCache();

      // Then restart Firebase
      await FirebaseConfig.restartFirebase();

      // Test a simple read to verify recovery
      await _firestore.collection('posts').limit(1).get();

      print('✅ Manual recovery successful');
      return true;
    } catch (e) {
      print('❌ Manual recovery failed: $e');
      await _errorHandler.handleFirebaseException(e, context);
      return false;
    }
  }

  // Clean up resources when no longer needed
  void dispose() {
    _errorController.close();
  }

  // Initialize posts collection with a sample post
  Future<void> initializePostsCollection({BuildContext? context}) async {
    if (currentUserId == null) return;

    try {
      // Check if posts collection exists and has documents
      final postsSnapshot = await _firestore.collection('posts').limit(1).get();

      if (postsSnapshot.docs.isEmpty) {
        print('🔄 Initializing posts collection with sample data...');

        // Get user data for the sample post
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(currentUserId).get();

        if (!userDoc.exists) {
          throw Exception("User document doesn't exist!");
        }

        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        // Create a sample post
        Post samplePost = Post(
          id: '', // Will be set by Firestore
          userId: currentUserId!,
          username: userData['username'] ?? 'Anonymous',
          userProfileImage: userData['profileImageUrl'] ?? '',
          caption: 'Welcome to my first post! 👋',
          imageUrl:
              'https://picsum.photos/seed/sample/500/500', // Random placeholder image
          timestamp: DateTime.now(),
          likes: [],
          commentsCount: 0,
          location: 'Sample Location',
        );

        await _firestore.collection('posts').add(samplePost.toMap());
        print('✅ Posts collection initialized successfully');
      }
    } catch (e) {
      print('❌ Error initializing posts collection: $e');
      _errorController.add("Couldn't initialize posts. Please try again.");
      await _errorHandler.handleFirebaseException(e, context);
      rethrow;
    }
  }
}
