import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';

/// Centralized chat list state provider.
///
/// Holds a single Firestore real-time listener for the current user's chats,
/// a user-info cache that survives widget rebuilds, and exposes filtered views
/// for the UI.  Because it lives in the Provider tree it is never destroyed
/// when tabs switch or navigation pushes/pops screens.
class ChatProvider extends ChangeNotifier {
  // ── Firestore subscription ────────────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _chatsSubscription;
  StreamSubscription<User?>? _authSubscription;
  bool _isSubscribed = false;

  // ── Snapshot data ─────────────────────────────────────────────────────
  List<DocumentSnapshot> _chatDocs = [];
  bool _isLoading = true;
  String? _error;

  // ── User info cache ───────────────────────────────────────────────────
  final Map<String, Map<String, String>> userInfoCache = {};
  final Map<String, Future<Map<String, String>>> _pendingUserFetches = {};

  // ── Public getters ────────────────────────────────────────────────────
  List<DocumentSnapshot> get chatDocs => _chatDocs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Call once (e.g. from main.dart or the first consumer's initState).
  /// Guards against duplicate subscriptions.
  void initialize() {
    if (_isSubscribed) return;
    _isSubscribed = true;

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        _subscribeToChatList(user.uid);
      } else {
        _clearData();
      }
    });
  }

  void _subscribeToChatList(String uid) {
    // Cancel any existing chat subscription (e.g. on re-auth)
    _chatsSubscription?.cancel();

    if (PlatformHelper.isWindows &&
        !FirebaseConfig.isFirebaseEnabledOnWindows) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _chatsSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('userIds', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snapshot) {
        final filtered = snapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['isDeleted'] != true;
        }).toList();

        _chatDocs = filtered;
        _isLoading = false;
        _error = null;

        // Pre-fetch partner info in the background
        _prefetchUserInfo(filtered, uid);

        notifyListeners();
      },
      onError: (error) {
        if (error.toString().contains('requires an index')) {
          debugPrint(
              'Index error detected. Deploy the index in firestore.indexes.json');
        }
        _error = error.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  void _clearData() {
    _chatsSubscription?.cancel();
    _chatsSubscription = null;
    _chatDocs = [];
    _isLoading = true;
    _error = null;
    // Don't clear userInfoCache – it's fine to keep across sign-out for fast
    // re-render if the same user signs back in.
    notifyListeners();
  }

  // ── User info fetching ────────────────────────────────────────────────

  /// Get cached info for a given other-user ID, or null if not yet loaded.
  Map<String, String>? getCachedUserInfo(String userId) {
    return userInfoCache[userId];
  }

  /// Fetch a single user's info (with dedup + cache).
  Future<Map<String, String>> fetchUserInfo(String userId) async {
    if (userInfoCache.containsKey(userId)) {
      return userInfoCache[userId]!;
    }
    if (_pendingUserFetches.containsKey(userId)) {
      return _pendingUserFetches[userId]!;
    }

    final future = _doFetchUserInfo(userId);
    _pendingUserFetches[userId] = future;

    try {
      final result = await future;
      userInfoCache[userId] = result;
      _pendingUserFetches.remove(userId);
      notifyListeners(); // let widgets that showed shimmer re-render
      return result;
    } catch (e) {
      _pendingUserFetches.remove(userId);
      rethrow;
    }
  }

  Future<Map<String, String>> _doFetchUserInfo(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (doc.exists) {
        return {
          'name': doc.data()?['username'] ?? 'Unknown',
          'profileImageUrl': doc.data()?['profileImageUrl'] ?? '',
        };
      }
    } catch (e) {
      debugPrint('Error fetching user $userId: $e');
    }
    return {'name': 'Unknown', 'profileImageUrl': ''};
  }

  /// Batch-fetch many users at once (Firestore `whereIn` in chunks of 10).
  Future<void> batchFetchUsers(Set<String> userIds) async {
    final uncached = userIds
        .where((id) => id.isNotEmpty && !userInfoCache.containsKey(id))
        .toList();
    if (uncached.isEmpty) return;

    const chunkSize = 10;
    bool didAdd = false;

    for (int i = 0; i < uncached.length; i += chunkSize) {
      final chunk = uncached.skip(i).take(chunkSize).toList();
      final validChunk = chunk.where((id) => id.isNotEmpty).toList();
      if (validChunk.isEmpty) continue;

      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: validChunk)
            .get();

        for (final doc in snap.docs) {
          userInfoCache[doc.id] = {
            'name': (doc.data()['username'] ?? 'Unknown') as String,
            'profileImageUrl':
                (doc.data()['profileImageUrl'] ?? '') as String,
          };
          didAdd = true;
        }

        // Mark missing users so we don't re-query them
        for (final id in chunk) {
          if (!userInfoCache.containsKey(id)) {
            userInfoCache[id] = {'name': 'Unknown', 'profileImageUrl': ''};
            didAdd = true;
          }
        }
      } catch (e) {
        debugPrint('Error batch fetching users: $e');
      }
    }

    if (didAdd) notifyListeners();
  }

  void _prefetchUserInfo(List<DocumentSnapshot> chats, String currentUid) {
    final ids = <String>{};
    for (final chat in chats) {
      final data = chat.data() as Map<String, dynamic>;
      final userIds = List<String>.from(data['userIds'] ?? []);
      ids.addAll(userIds.where((id) => id != currentUid));
    }
    if (ids.isNotEmpty) {
      batchFetchUsers(ids);
    }
  }

  // ── Filtering (pure, no side-effects) ─────────────────────────────────

  /// Return chats matching [query]. If query is empty returns all non-deleted.
  List<DocumentSnapshot> getFilteredChats(String query) {
    if (query.isEmpty) return _chatDocs;

    final lowerQuery = query.toLowerCase();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return _chatDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final lastMessage =
          (data['lastMessage'] ?? '').toString().toLowerCase();

      final userIds = List<String>.from(data['userIds'] ?? []);
      final otherUserId = userIds.firstWhere(
        (id) => id != currentUid,
        orElse: () => '',
      );

      String userName = '';
      if (otherUserId.isNotEmpty &&
          userInfoCache.containsKey(otherUserId)) {
        userName =
            userInfoCache[otherUserId]!['name']?.toLowerCase() ?? '';
      }

      return lastMessage.contains(lowerQuery) ||
          userName.contains(lowerQuery);
    }).toList();
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    _authSubscription?.cancel();
    _pendingUserFetches.clear();
    super.dispose();
  }
}
