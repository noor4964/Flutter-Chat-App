import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/models/comment_model.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/main.dart' show navigatorKey;
import '../services/firebase_config.dart';
import 'dart:async';

class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Maximum number of IDs for whereIn query (Firestore limit is 10)
  static const int _maxWhereInLimit = 10;

  // Flag to check if we're on Windows with Firebase disabled
  bool get _isWindowsWithoutFirebase =>
      PlatformHelper.isWindows && !FirebaseConfig.isFirebaseEnabledOnWindows;

  // Flag to check if we're on web
  bool get _isWeb => kIsWeb;

  // Create a new post
  Future<String?> createPost({
    required String caption,
    required String imageUrl,
    List<String> imageUrls = const [],
    required PostPrivacy privacy,
    String location = '',
  }) async {
    if (_isWindowsWithoutFirebase) {
      print('Post creation skipped on Windows');
      return 'windows-mock-post-id';
    }

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get user data for post
      final userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      if (!userDoc.exists) {
        throw Exception('User profile not found');
      }

      final userData = userDoc.data()!;

      // Convert enum to string for storage
      String privacyString;
      switch (privacy) {
        case PostPrivacy.public:
          privacyString = 'public';
          break;
        case PostPrivacy.friends:
          privacyString = 'friends';
          break;
        case PostPrivacy.private:
          privacyString = 'private';
          break;
      }

      // Build the list of all image URLs
      final List<String> allUrls = imageUrls.isNotEmpty
          ? imageUrls
          : (imageUrl.isNotEmpty ? [imageUrl] : []);

      // Create post document
      DocumentReference postRef = await _firestore.collection('posts').add({
        'userId': currentUser.uid,
        'username': userData['username'] ?? 'Anonymous',
        'userProfileImage': userData['profileImageUrl'] ?? '',
        'caption': caption,
        'imageUrl': allUrls.isNotEmpty ? allUrls.first : imageUrl,
        'imageUrls': allUrls,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': [],
        'commentsCount': 0,
        'location': location,
        'privacy': privacyString,
      });

      print('Post created with ID: ${postRef.id}');
      return postRef.id;
    } catch (e) {
      print('Error creating post: $e');
      print('Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  // Get feed posts with privacy filtering
  Stream<List<Post>> getFeedPosts() {
    if (_isWindowsWithoutFirebase) {
      // Return empty stream on Windows
      print('Post Service: Running on Windows without Firebase, returning empty stream');
      return Stream.value([]);
    }

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('Post Service: No authenticated user, returning empty stream');
        return Stream.value([]); // Return empty if not authenticated
      }

      // Create a stream controller to manage the posts feed
      final controller = StreamController<List<Post>>();

      // Function to load and process posts
      void loadPosts() async {
        try {
          print('Post Service: Loading posts for user ${currentUser.uid}');
          
          // First, get user friends to filter 'friends' privacy posts
          final friendIds = await _getFriendsList(currentUser.uid);
          print('Post Service: Found ${friendIds.length} friends for privacy filtering');
          
          // Initialize collections to store unique post documents and IDs
          final List<QueryDocumentSnapshot> allDocs = [];
          final Set<String> addedPostIds = {};
          
          // Query public posts - simple query with just one condition and ordering
          print('Post Service: Querying public posts');
          final publicPostsQuery = _firestore
              .collection('posts')
              .where('privacy', isEqualTo: 'public')
              .orderBy('timestamp', descending: true)
              .limit(50);
              
          // Query the current user's posts - separate queries by privacy type
          // This avoids the need for complex compound indexes
          print('Post Service: Querying current user posts');
          final userPostsQuery = _firestore
              .collection('posts')
              .where('userId', isEqualTo: currentUser.uid)
              .orderBy('timestamp', descending: true);

          // Get all queryable posts
          List<QuerySnapshot> snapshots = [];
          
          // Get public posts
          final publicSnapshot = await publicPostsQuery.get();
          print('Post Service: Retrieved ${publicSnapshot.docs.length} public posts');
          snapshots.add(publicSnapshot);
          
          // Get current user's posts (all privacy levels)
          final userSnapshot = await userPostsQuery.get();
          print('Post Service: Retrieved ${userSnapshot.docs.length} posts by current user');
          snapshots.add(userSnapshot);

          // If the user has friends, get their posts with 'friends' privacy
          if (friendIds.isNotEmpty) {
            print('Post Service: Querying friend posts with privacy=friends');
            // Handle Firestore's "in" query limitation (max 10 values)
            // Split friend IDs into chunks of 10 or fewer
            for (int i = 0; i < friendIds.length; i += _maxWhereInLimit) {
              final endIndex = (i + _maxWhereInLimit < friendIds.length)
                  ? i + _maxWhereInLimit
                  : friendIds.length;

              final chunk = friendIds.sublist(i, endIndex);
              print('Post Service: Processing friend chunk ${i ~/ _maxWhereInLimit + 1} with ${chunk.length} friends');

              // Instead of compound query, we'll fetch all friend posts and filter in code
              // This avoids the index requirement
              final friendsPostsQuery = _firestore
                  .collection('posts')
                  .where('userId', whereIn: chunk)
                  .orderBy('timestamp', descending: true);

              final friendsSnapshot = await friendsPostsQuery.get();
              print('Post Service: Retrieved ${friendsSnapshot.docs.length} friend posts from chunk');
              
              // Only keep friends posts with 'friends' privacy - filter docs manually
              final friendsFilteredDocs = friendsSnapshot.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['privacy'] == 'friends';
              }).toList();
              
              if (friendsFilteredDocs.isNotEmpty) {
                // Add filtered friend posts to allDocs directly instead of trying to create a new QuerySnapshot
                for (var doc in friendsFilteredDocs) {
                  if (!addedPostIds.contains(doc.id)) {
                    allDocs.add(doc);
                    addedPostIds.add(doc.id);
                  }
                }
                print('Post Service: Added ${friendsFilteredDocs.length} friend posts with friends privacy');
              }
            }
          }

          // Combine all matching posts from public and user posts queries
          for (var snapshot in snapshots) {
            for (var doc in snapshot.docs) {
              if (!addedPostIds.contains(doc.id)) {
                allDocs.add(doc);
                addedPostIds.add(doc.id);
              }
            }
          }

          print('Post Service: Combined ${allDocs.length} unique posts after deduplication');

          // Sort combined results by timestamp
          allDocs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            Timestamp? aTimestamp = aData['timestamp'] as Timestamp?;
            Timestamp? bTimestamp = bData['timestamp'] as Timestamp?;

            if (aTimestamp == null && bTimestamp == null) return 0;
            if (aTimestamp == null) return 1;
            if (bTimestamp == null) return -1;

            return bTimestamp.compareTo(aTimestamp); // Descending order
          });

          // Convert to Post objects
          final posts = allDocs.map((doc) {
            try {
              return Post.fromFirestore(doc);
            } catch (e) {
              print('Post Service: Error creating Post from doc ${doc.id}: $e');
              // Return null for posts with errors
              return null;
            }
          }).where((post) => post != null).cast<Post>().toList();
          
          print('Post Service: Final post count after filtering: ${posts.length}');
          
          // Add to stream if controller is still active
          if (!controller.isClosed) {
            controller.add(posts);
          }
        } catch (e) {
          print('Post Service: Error getting feed posts: $e');
          print('Post Service: Stack trace: ${StackTrace.current}');
          if (!controller.isClosed) {
            controller.add([]);
          }
        }
      }

      // Initial load
      loadPosts();

      // Set up listener for updates to posts collection
      final listener = _firestore
          .collection('posts')
          .snapshots()
          .listen((_) {
        // Reload posts when any changes occur
        print('Post Service: Posts collection updated, reloading data');
        loadPosts();
      });

      // Clean up when the stream is closed
      controller.onCancel = () {
        listener.cancel();
        controller.close();
      };

      return controller.stream;
    } catch (e) {
      print('Post Service: Error setting up feed posts stream: $e');
      print('Post Service: Stack trace: ${StackTrace.current}');
      return Stream.value([]);
    }
  }

  // Get user-specific posts
  Stream<List<Post>> getUserPosts(String userId, {bool includePrivate = false}) {
    if (_isWindowsWithoutFirebase) {
      return Stream.value([]);
    }

    try {
      final User? currentUser = _auth.currentUser;
      final bool isOwnProfile = currentUser?.uid == userId;

      // Create a stream controller to handle the complex filtering
      final controller = StreamController<List<Post>>();

      // Fetch posts based on appropriate queries
      void fetchPosts() async {
        try {
          List<Post> allPosts = [];

          // Get public posts for this user
          final publicSnapshot = await _firestore
              .collection('posts')
              .where('userId', isEqualTo: userId)
              .where('privacy', isEqualTo: 'public')
              .orderBy('timestamp', descending: true)
              .get();

          // Add public posts
          for (var doc in publicSnapshot.docs) {
            allPosts.add(Post.fromFirestore(doc));
          }

          // Include private posts if viewing own profile
          if (isOwnProfile && includePrivate) {
            final privateSnapshot = await _firestore
                .collection('posts')
                .where('userId', isEqualTo: userId)
                .where('privacy', isEqualTo: 'private')
                .orderBy('timestamp', descending: true)
                .get();

            for (var doc in privateSnapshot.docs) {
              allPosts.add(Post.fromFirestore(doc));
            }
          }

          // Check friendship status before adding friends-only posts
          final isFriend = await _checkFriendshipStatus(
              currentUser?.uid ?? '', userId);

          // Include friends-only posts if friends or own profile
          if (isOwnProfile || isFriend) {
            final friendsSnapshot = await _firestore
                .collection('posts')
                .where('userId', isEqualTo: userId)
                .where('privacy', isEqualTo: 'friends')
                .orderBy('timestamp', descending: true)
                .get();

            for (var doc in friendsSnapshot.docs) {
              allPosts.add(Post.fromFirestore(doc));
            }
          }

          // Sort all posts by timestamp (newest first)
          allPosts.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          // Add posts to stream
          if (!controller.isClosed) {
            controller.add(allPosts);
          }
        } catch (e) {
          print('Error fetching user posts: $e');
          if (!controller.isClosed) {
            controller.add([]);
          }
        }
      }

      // Initial fetch
      fetchPosts();

      // Set up listener for future updates
      final listener = _firestore
          .collection('posts')
          .where('userId', isEqualTo: userId)
          .snapshots()
          .listen((_) {
        // When posts change, refetch with proper filtering
        fetchPosts();
      });

      // Clean up when the stream is done
      controller.onCancel = () {
        listener.cancel();
        controller.close();
      };

      return controller.stream;
    } catch (e) {
      print('Error setting up user posts stream: $e');
      return Stream.value([]);
    }
  }

  // Like or unlike a post (transaction-safe)
  Future<bool> toggleLike(String postId) async {
    if (_isWindowsWithoutFirebase) return false;

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final postRef = _firestore.collection('posts').doc(postId);

      // Store post owner ID outside transaction scope
      String? postOwnerId;

      final isNowLiked =
          await _firestore.runTransaction<bool>((transaction) async {
        final postDoc = await transaction.get(postRef);
        if (!postDoc.exists) {
          throw Exception('Post not found');
        }

        final postData = postDoc.data()!;
        final likes = List<String>.from(postData['likes'] ?? []);
        final bool wasLiked = likes.contains(currentUser.uid);
        postOwnerId = postData['userId'] as String?;

        if (wasLiked) {
          likes.remove(currentUser.uid);
        } else {
          likes.add(currentUser.uid);
        }

        transaction.update(postRef, {'likes': likes});
        return !wasLiked; // true if now liked, false if now unliked
      });

      // Log activity AFTER transaction succeeds
      print('toggleLike: isNowLiked=$isNowLiked, postOwnerId=$postOwnerId, currentUser=${currentUser.uid}');
      _debugSnackBar('toggleLike: liked=$isNowLiked owner=$postOwnerId');
      if (postOwnerId != null && postOwnerId != currentUser.uid) {
        if (isNowLiked) {
          print('toggleLike: calling _logActivity for like');
          await _logActivity(
            type: 'like',
            actorId: currentUser.uid,
            recipientId: postOwnerId!,
            postId: postId,
          );
        } else {
          print('toggleLike: calling _removeLikeActivity (unliked)');
          await _removeLikeActivity(actorId: currentUser.uid, postId: postId);
        }
      } else {
        print('toggleLike: skipped activity log (own post or null owner)');
      }

      return isNowLiked;
    } catch (e) {
      print('Error toggling like: $e');
      rethrow;
    }
  }

  // ── Comment CRUD ────────────────────────────────────────────────────

  /// Add a comment to a post. Returns the created [Comment].
  Future<Comment> addComment(String postId, String text) async {
    if (_isWindowsWithoutFirebase) {
      throw Exception('Comments not available on Windows');
    }

    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    // Get user profile data for denormalized fields
    final userDoc =
        await _firestore.collection('users').doc(currentUser.uid).get();
    final userData = userDoc.data() ?? {};

    final commentRef = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc();

    final commentData = {
      'userId': currentUser.uid,
      'username': userData['username'] ?? 'Anonymous',
      'userProfileImage': userData['profileImageUrl'] ?? '',
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': <String>[],
    };

    // Batch: create comment + increment commentsCount atomically
    final batch = _firestore.batch();
    batch.set(commentRef, commentData);
    batch.update(
      _firestore.collection('posts').doc(postId),
      {'commentsCount': FieldValue.increment(1)},
    );
    await batch.commit();

    // Log activity for post owner
    final postDoc = await _firestore.collection('posts').doc(postId).get();
    final postOwnerId = postDoc.data()?['userId'] as String?;
    if (postOwnerId != null && postOwnerId != currentUser.uid) {
      print('addComment: calling _logActivity for comment');
      await _logActivity(
        type: 'comment',
        actorId: currentUser.uid,
        recipientId: postOwnerId,
        postId: postId,
        commentPreview: text.length > 100 ? '${text.substring(0, 100)}...' : text,
      );
    }

    // Return a local Comment for immediate UI update
    return Comment(
      id: commentRef.id,
      postId: postId,
      userId: currentUser.uid,
      username: userData['username'] ?? 'Anonymous',
      userProfileImage: userData['profileImageUrl'] ?? '',
      text: text,
      timestamp: DateTime.now(),
      likes: [],
    );
  }

  /// Delete a comment. Only the comment author can delete.
  Future<void> deleteComment(String postId, String commentId) async {
    if (_isWindowsWithoutFirebase) return;

    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final batch = _firestore.batch();
    batch.delete(
      _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId),
    );
    batch.update(
      _firestore.collection('posts').doc(postId),
      {'commentsCount': FieldValue.increment(-1)},
    );
    await batch.commit();
  }

  /// Real-time stream of comments for a post, ordered newest first.
  Stream<List<Comment>> getComments(String postId) {
    if (_isWindowsWithoutFirebase) return Stream.value([]);

    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Comment.fromFirestore(doc, postId: postId))
            .toList());
  }

  /// Toggle like on a comment (transaction-safe).
  Future<void> toggleCommentLike(String postId, String commentId) async {
    if (_isWindowsWithoutFirebase) return;

    final User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final commentRef = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(commentRef);
      if (!doc.exists) return;

      final likes = List<String>.from(doc.data()?['likes'] ?? []);
      if (likes.contains(currentUser.uid)) {
        likes.remove(currentUser.uid);
      } else {
        likes.add(currentUser.uid);
      }
      transaction.update(commentRef, {'likes': likes});
    });
  }

  // Delete a post
  Future<void> deletePost(String postId) async {
    if (_isWindowsWithoutFirebase) return;

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get the post
      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (!postDoc.exists) {
        throw Exception('Post not found');
      }

      final postData = postDoc.data()!;

      // Check if current user is the post owner
      if (postData['userId'] != currentUser.uid) {
        throw Exception('You can only delete your own posts');
      }

      // Delete the post
      await _firestore.collection('posts').doc(postId).delete();
    } catch (e) {
      print('Error deleting post: $e');
    }
  }

  // Update post privacy
  Future<void> updatePrivacy(String postId, PostPrivacy privacy) async {
    if (_isWindowsWithoutFirebase) return;

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get the post
      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (!postDoc.exists) {
        throw Exception('Post not found');
      }

      final postData = postDoc.data()!;

      // Check if current user is the post owner
      if (postData['userId'] != currentUser.uid) {
        throw Exception('You can only update your own posts');
      }

      // Convert enum to string
      String privacyString;
      switch (privacy) {
        case PostPrivacy.public:
          privacyString = 'public';
          break;
        case PostPrivacy.friends:
          privacyString = 'friends';
          break;
        case PostPrivacy.private:
          privacyString = 'private';
          break;
      }

      // Update the post privacy
      await _firestore.collection('posts').doc(postId).update({
        'privacy': privacyString,
      });
    } catch (e) {
      print('Error updating post privacy: $e');
    }
  }

  // Helper method to get user's friends list
  Future<List<String>> _getFriendsList(String userId) async {
    try {
      // Query connections where user is involved and status is accepted
      final snapshot = await _firestore
          .collection('connections')
          .where('status', isEqualTo: 'accepted')
          .where(Filter.or(
              Filter('senderId', isEqualTo: userId),
              Filter('receiverId', isEqualTo: userId)))
          .get();

      // Extract friend IDs (take the OTHER user's ID from each connection)
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return data['senderId'] == userId
            ? data['receiverId'] as String
            : data['senderId'] as String;
      }).toList();
    } catch (e) {
      print('Error getting friends list: $e');
      return [];
    }
  }

  // Helper method to check friendship status between two users
  Future<bool> _checkFriendshipStatus(String userId1, String userId2) async {
    if (userId1.isEmpty || userId2.isEmpty || userId1 == userId2) {
      return userId1 == userId2;
    }

    try {
      final snapshot = await _firestore
          .collection('connections')
          .where('status', isEqualTo: 'accepted')
          .where(Filter.or(
              Filter.and(Filter('senderId', isEqualTo: userId1),
                  Filter('receiverId', isEqualTo: userId2)),
              Filter.and(Filter('senderId', isEqualTo: userId2),
                  Filter('receiverId', isEqualTo: userId1))))
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking friendship status: $e');
      return false;
    }
  }

  // ── Activity logging ────────────────────────────────────────────────

  /// TEMP DEBUG: Show a visible SnackBar using the global navigator key.
  void _debugSnackBar(String message, {bool isError = false}) {
    try {
      final context = navigatorKey.currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.red : Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {}
  }

  /// Log an activity (like, comment) to the activities collection so it
  /// appears in the recipient's notification feed.
  Future<void> _logActivity({
    required String type,
    required String actorId,
    required String recipientId,
    required String postId,
    String? commentPreview,
  }) async {
    try {
      print('_logActivity: START type=$type actorId=$actorId recipientId=$recipientId postId=$postId');
      _debugSnackBar('_logActivity: START $type for post $postId');
      // Fetch actor profile for denormalized fields
      final actorDoc =
          await _firestore.collection('users').doc(actorId).get();
      final actorData = actorDoc.data() ?? {};
      print('_logActivity: got actor data, username=${actorData['username']}');

      final docRef = await _firestore.collection('activities').add({
        'type': type,
        'actorId': actorId,
        'actorName': actorData['username'] ?? 'Someone',
        'actorImage': actorData['profileImageUrl'] ?? '',
        'recipientId': recipientId,
        'postId': postId,
        if (commentPreview != null) 'commentPreview': commentPreview,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      print('_logActivity: SUCCESS created activity doc ${docRef.id}');
      _debugSnackBar('Activity logged OK! doc=${docRef.id}');
    } catch (e) {
      print('_logActivity: ERROR $e');
      _debugSnackBar('_logActivity ERROR: $e', isError: true);
      // Don't rethrow - activity logging failure shouldn't block the main action
    }
  }

  /// Remove a like activity when the user unlikes a post.
  Future<void> _removeLikeActivity({
    required String actorId,
    required String postId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('activities')
          .where('type', isEqualTo: 'like')
          .where('actorId', isEqualTo: actorId)
          .where('postId', isEqualTo: postId)
          .limit(1)
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      print('Error removing like activity: $e');
    }
  }
}
