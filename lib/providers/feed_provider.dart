import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/models/comment_model.dart';
import 'package:flutter_chat_app/models/story_model.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';
import 'package:flutter_chat_app/services/post_service.dart';
import 'package:flutter_chat_app/services/story_service.dart';

/// Centralized feed state provider.
///
/// Holds a single Firestore real-time listener for posts, a story stream,
/// in-memory cache, cursor-based pagination, and auth-awareness.
/// Lives in the Provider tree so it survives tab switches and navigation.
class FeedProvider extends ChangeNotifier {
  // ── Configuration ─────────────────────────────────────────────────────
  static const int _pageSize = 20;
  static const int _maxWhereInLimit = 10;

  // ── Firestore subscriptions ───────────────────────────────────────────
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot>? _postsSubscription;
  StreamSubscription<List<Story>>? _storiesSubscription;
  bool _isSubscribed = false;

  // ── Posts data ────────────────────────────────────────────────────────
  List<Post> _posts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  String? _error;
  DocumentSnapshot? _lastDocument;

  // ── Stories data ──────────────────────────────────────────────────────
  final StoryService _storyService = StoryService();
  Map<String, List<Story>> _groupedStories = {};
  bool _isLoadingStories = true;

  // ── User info cache ─────────────────────────────────────────────
  String? _currentUserProfileImageUrl;
  String? _currentUsername;
  String? _currentUserId;
  bool _hasActiveStory = false;

  // ── Scroll position cache (survives widget disposal) ───────────────
  double savedScrollOffset = 0.0;

  // ── Offline / cache awareness ──────────────────────────────────────
  /// True when the most-recent snapshot came from the local Firestore cache
  /// rather than the server.  Useful for showing "cached data" indicators.
  bool _isFromCache = false;

  /// Timestamp of the last snapshot that came from the Firestore server
  /// (i.e. not from local cache).  `null` means we have never received a
  /// server snapshot in this session.
  DateTime? _lastServerSync;

  // ── Friends cache (for privacy filtering) ─────────────────────────────
  List<String> _friendIds = [];
  DateTime? _friendsCacheTime;
  static const Duration _friendsCacheDuration = Duration(minutes: 10);

  // ── PostService for mutations ─────────────────────────────────────────
  final PostService _postService = PostService();

  // ── Public getters ────────────────────────────────────────────────────
  List<Post> get posts => _posts;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMorePosts => _hasMorePosts;
  String? get error => _error;
  Map<String, List<Story>> get groupedStories => _groupedStories;
  bool get isLoadingStories => _isLoadingStories;
  String? get currentUserProfileImageUrl => _currentUserProfileImageUrl;
  String? get currentUsername => _currentUsername;
  String? get currentUserId => _currentUserId;
  bool get hasActiveStory => _hasActiveStory;
  StoryService get storyService => _storyService;
  bool get isFromCache => _isFromCache;
  DateTime? get lastServerSync => _lastServerSync;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Call once from main.dart. Guards against duplicate subscriptions.
  void initialize() {
    if (_isSubscribed) return;
    _isSubscribed = true;

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        _currentUserId = user.uid;
        _loadCurrentUserInfo(user.uid);
        _loadFriendsList(user.uid);
        _subscribeToPosts(user.uid);
        _subscribeToStories();
      } else {
        _clearData();
      }
    });
  }

  // ── Posts subscription ────────────────────────────────────────────────

  void _subscribeToPosts(String uid) {
    _postsSubscription?.cancel();

    if (PlatformHelper.isWindows &&
        !FirebaseConfig.isFirebaseEnabledOnWindows) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Only show full loading state if the cache is empty.
    // Re-subscriptions (auth token refresh, pull-to-refresh) should not
    // flash the skeleton when cached posts already exist.
    if (_posts.isEmpty) {
      _isLoading = true;
    }
    _error = null;
    notifyListeners();

    // Listen to recent posts ordered by timestamp.
    // `includeMetadataChanges: true` means we receive an extra snapshot
    // immediately from the local disk-cache *before* the server round-trip
    // completes — giving the user instant content on cold starts.
    _postsSubscription = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(_pageSize)
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snapshot) {
        // Track whether this data came from Firestore cache or network.
        final fromCache = snapshot.metadata.isFromCache;
        _isFromCache = fromCache;
        if (!fromCache) {
          _lastServerSync = DateTime.now();
        }

        _processPostsSnapshot(snapshot, uid, isLoadMore: false);
      },
      onError: (error) {
        debugPrint('Error in posts stream: $error');
        _error = 'Unable to load feed. Pull to refresh.';
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  void _processPostsSnapshot(
    QuerySnapshot snapshot,
    String uid, {
    required bool isLoadMore,
  }) {
    try {
      final allDocs = snapshot.docs;

      // Filter by privacy: public, own posts, or friend's "friends" posts
      final filteredDocs = allDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final privacy = data['privacy'] ?? 'public';
        final postUserId = data['userId'] ?? '';

        // Own posts always visible
        if (postUserId == uid) return true;
        // Public posts always visible
        if (privacy == 'public') return true;
        // Friends-only posts visible if the poster is a friend
        if (privacy == 'friends' && _friendIds.contains(postUserId)) {
          return true;
        }
        // Private posts only visible to creator (already handled above)
        return false;
      }).toList();

      final newPosts = filteredDocs.map((doc) {
        try {
          return Post.fromFirestore(doc);
        } catch (e) {
          debugPrint('Error parsing post ${doc.id}: $e');
          return null;
        }
      }).whereType<Post>().toList();

      if (isLoadMore) {
        // Append to existing, dedup by ID
        final existingIds = _posts.map((p) => p.id).toSet();
        final uniqueNew =
            newPosts.where((p) => !existingIds.contains(p.id)).toList();
        _posts.addAll(uniqueNew);
      } else {
        _posts = newPosts;
      }

      // Track pagination cursor
      if (allDocs.isNotEmpty) {
        _lastDocument = allDocs.last;
      }
      _hasMorePosts = allDocs.length >= _pageSize;

      _isLoading = false;
      _isLoadingMore = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error processing posts: $e');
      _error = 'Error processing feed data.';
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Load the next page of posts (cursor-based pagination).
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMorePosts || _lastDocument == null) return;

    final uid = _currentUserId;
    if (uid == null) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      // Try server-first for freshest data.
      QuerySnapshot snapshot;
      try {
        snapshot = await FirebaseFirestore.instance
            .collection('posts')
            .orderBy('timestamp', descending: true)
            .startAfterDocument(_lastDocument!)
            .limit(_pageSize)
            .get(const GetOptions(source: Source.serverAndCache));
        _isFromCache = snapshot.metadata.isFromCache;
        if (!snapshot.metadata.isFromCache) {
          _lastServerSync = DateTime.now();
        }
      } catch (_) {
        // Network unavailable — fall back to local cache so the user can
        // still scroll through previously fetched posts.
        snapshot = await FirebaseFirestore.instance
            .collection('posts')
            .orderBy('timestamp', descending: true)
            .startAfterDocument(_lastDocument!)
            .limit(_pageSize)
            .get(const GetOptions(source: Source.cache));
        _isFromCache = true;
      }

      _processPostsSnapshot(snapshot, uid, isLoadMore: true);
    } catch (e) {
      debugPrint('Error loading more posts: $e');
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // ── Social Interaction Methods ──────────────────────────────────────

  /// Optimistically toggle like on a post, then persist via PostService.
  /// Reverts local state on failure.
  Future<void> toggleLike(String postId) async {
    final uid = _currentUserId;
    if (uid == null) return;

    // Find post index
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;

    // Snapshot for rollback
    final original = _posts[idx];
    final wasLiked = original.likes.contains(uid);
    final newLikes = List<String>.from(original.likes);

    if (wasLiked) {
      newLikes.remove(uid);
    } else {
      newLikes.add(uid);
    }

    // Optimistic update
    _posts[idx] = original.copyWith(likes: newLikes);
    notifyListeners();

    try {
      await _postService.toggleLike(postId);
    } catch (e) {
      // Revert on failure
      debugPrint('toggleLike failed, reverting: $e');
      _posts[idx] = original;
      notifyListeners();
    }
  }

  /// Add a comment to a post. Optimistically increments commentsCount.
  Future<Comment?> addComment(String postId, String text) async {
    if (text.trim().isEmpty) return null;

    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return null;

    // Optimistic: increment commentsCount locally
    final original = _posts[idx];
    _posts[idx] = original.copyWith(commentsCount: original.commentsCount + 1);
    notifyListeners();

    try {
      final comment = await _postService.addComment(postId, text.trim());
      return comment;
    } catch (e) {
      // Revert on failure
      debugPrint('addComment failed, reverting: $e');
      _posts[idx] = original;
      notifyListeners();
      return null;
    }
  }

  /// Delete a comment from a post. Optimistically decrements commentsCount.
  Future<void> deleteComment(String postId, String commentId) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;

    // Optimistic: decrement commentsCount locally
    final original = _posts[idx];
    _posts[idx] = original.copyWith(
      commentsCount: (original.commentsCount - 1).clamp(0, 999999),
    );
    notifyListeners();

    try {
      await _postService.deleteComment(postId, commentId);
    } catch (e) {
      debugPrint('deleteComment failed, reverting: $e');
      _posts[idx] = original;
      notifyListeners();
    }
  }

  /// Pull-to-refresh: cancel current listener and re-subscribe fresh.
  Future<void> refresh() async {
    final uid = _currentUserId;
    if (uid == null) return;

    _lastDocument = null;
    _hasMorePosts = true;

    // Refresh friends list if stale
    await _loadFriendsList(uid);

    // Re-subscribe to get fresh data
    _subscribeToPosts(uid);

    // Also refresh stories
    _subscribeToStories();

    // Refresh user info
    _loadCurrentUserInfo(uid);

    // Check active story
    _checkForActiveUserStory();
  }

  // ── Stories subscription ──────────────────────────────────────────────

  void _subscribeToStories() {
    _storiesSubscription?.cancel();

    _isLoadingStories = true;

    try {
      _storiesSubscription =
          _storyService.getActiveStories().listen(
        (stories) {
          _groupedStories = _storyService.groupStoriesByUser(stories);
          _isLoadingStories = false;
          notifyListeners();
        },
        onError: (e) {
          debugPrint('Error in stories stream: $e');
          _isLoadingStories = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Error subscribing to stories: $e');
      _isLoadingStories = false;
      notifyListeners();
    }
  }

  // ── User info ─────────────────────────────────────────────────────────

  Future<void> _loadCurrentUserInfo(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _currentUsername = data['username'] as String?;
        _currentUserProfileImageUrl = data['profileImageUrl'] as String?;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading user info: $e');
    }
  }

  Future<void> _checkForActiveUserStory() async {
    if (_currentUserId == null) return;
    try {
      final userStories = await _storyService.getUserStoriesFuture(
        _currentUserId!,
      );
      _hasActiveStory = userStories.isNotEmpty;
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking active story: $e');
    }
  }

  // ── Friends list (for privacy filtering) ──────────────────────────────

  Future<void> _loadFriendsList(String uid) async {
    // Use cached friends if recent enough
    if (_friendsCacheTime != null &&
        DateTime.now().difference(_friendsCacheTime!) <
            _friendsCacheDuration) {
      return;
    }

    try {
      // Query connections collection where current user is involved and status is accepted
      final snapshot = await FirebaseFirestore.instance
          .collection('connections')
          .where('status', isEqualTo: 'accepted')
          .where(Filter.or(
              Filter('senderId', isEqualTo: uid),
              Filter('receiverId', isEqualTo: uid)))
          .get();

      // Extract friend IDs (take the OTHER user's ID from each connection)
      _friendIds = snapshot.docs.map((doc) {
        final data = doc.data();
        return data['senderId'] == uid
            ? data['receiverId'] as String
            : data['senderId'] as String;
      }).toList();

      _friendsCacheTime = DateTime.now();
    } catch (e) {
      debugPrint('Error loading friends list: $e');
      _friendIds = [];
    }
  }

  // ── Clear data ────────────────────────────────────────────────────────

  void _clearData() {
    _postsSubscription?.cancel();
    _postsSubscription = null;
    _storiesSubscription?.cancel();
    _storiesSubscription = null;
    _posts = [];
    _groupedStories = {};
    _isLoading = true;
    _isLoadingStories = true;
    _error = null;
    _lastDocument = null;
    _hasMorePosts = true;
    _currentUserId = null;
    _currentUsername = null;
    _currentUserProfileImageUrl = null;
    _friendIds = [];
    _friendsCacheTime = null;
    savedScrollOffset = 0.0;
    _isFromCache = false;
    _lastServerSync = null;
    notifyListeners();
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _postsSubscription?.cancel();
    _storiesSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
