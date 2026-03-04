import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';
import 'dart:convert';

/// Provides real-time notification data for the Instagram-like activity feed.
///
/// Tracks three streams:
/// 1. Pending friend requests (from `connections` collection)
/// 2. Activity feed – likes, comments (from `activities` collection)
/// 3. Incoming chat notifications (from `notifications/{uid}/user_notifications`)
///    – triggers local device notifications in real-time without needing
///    Firebase Cloud Functions.
class NotificationProvider extends ChangeNotifier {
  // ── Firestore subscriptions ───────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _connectionsSubscription;
  StreamSubscription<QuerySnapshot>? _activitiesSubscription;
  StreamSubscription<QuerySnapshot>? _chatNotifSubscription;
  StreamSubscription<User?>? _authSubscription;
  bool _isSubscribed = false;

  // ── Local notifications (for in-app real-time alerts) ─────────────
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _localNotifInitialized = false;

  // Track shown notification IDs to avoid duplicates on first load
  final Set<String> _shownNotificationIds = {};
  bool _initialChatLoadDone = false;

  // ── Data ──────────────────────────────────────────────────────────
  int _pendingRequestCount = 0;
  int _unreadActivityCount = 0;
  List<Map<String, dynamic>> _activities = [];

  // ── Public getters ────────────────────────────────────────────────
  int get pendingRequestCount => _pendingRequestCount;
  int get unreadActivityCount => _unreadActivityCount;
  int get totalUnreadCount => _pendingRequestCount + _unreadActivityCount;
  List<Map<String, dynamic>> get activities => _activities;

  // ── Lifecycle ─────────────────────────────────────────────────────

  /// Call once (e.g. from main.dart). Guards against duplicate subscriptions.
  void initialize() {
    if (_isSubscribed) return;
    _isSubscribed = true;

    _initLocalNotifications();

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        _subscribeToConnections(user.uid);
        _subscribeToActivities(user.uid);
        _subscribeToChatNotifications(user.uid);
      } else {
        _clearData();
      }
    });
  }

  // ── Local notification init ───────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    if (_localNotifInitialized) return;
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _localNotifications.initialize(settings);
      _localNotifInitialized = true;
    } catch (e) {
      debugPrint('NotificationProvider: Local notification init error: $e');
    }
  }

  // ── Friend request stream ─────────────────────────────────────────

  void _subscribeToConnections(String uid) {
    _connectionsSubscription?.cancel();

    if (PlatformHelper.isWindows &&
        !FirebaseConfig.isFirebaseEnabledOnWindows) {
      notifyListeners();
      return;
    }

    _connectionsSubscription = FirebaseFirestore.instance
        .collection('connections')
        .where('receiverId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
      (snapshot) {
        _pendingRequestCount = snapshot.docs.length;
        notifyListeners();
      },
      onError: (error) {
        debugPrint(
            'NotificationProvider: Error listening to connections: $error');
      },
    );
  }

  // ── Activities stream ─────────────────────────────────────────────

  void _subscribeToActivities(String uid) {
    _activitiesSubscription?.cancel();

    if (PlatformHelper.isWindows &&
        !FirebaseConfig.isFirebaseEnabledOnWindows) {
      return;
    }

    debugPrint('NotificationProvider: subscribing to activities for uid=$uid');

    _activitiesSubscription = FirebaseFirestore.instance
        .collection('activities')
        .where('recipientId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen(
      (snapshot) {
        debugPrint('NotificationProvider: activities snapshot received, ${snapshot.docs.length} docs');
        _activities = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            ...data,
          };
        }).toList();

        _unreadActivityCount =
            _activities.where((a) => a['isRead'] != true).length;

        debugPrint('NotificationProvider: unread=$_unreadActivityCount, total=${_activities.length}');
        notifyListeners();
      },
      onError: (error) {
        debugPrint(
            'NotificationProvider: ERROR listening to activities: $error');
        final errorStr = error.toString();
        if (errorStr.contains('index') || errorStr.contains('FAILED_PRECONDITION')) {
          debugPrint(
              'NotificationProvider: A composite Firestore index is needed. '
              'Check the Firebase console error log for the index creation link.');
        }
      },
    );
  }

  // ── Chat notifications stream (real-time local alerts) ────────────

  void _subscribeToChatNotifications(String uid) {
    _chatNotifSubscription?.cancel();
    _initialChatLoadDone = false;
    _shownNotificationIds.clear();

    if (PlatformHelper.isWindows &&
        !FirebaseConfig.isFirebaseEnabledOnWindows) {
      return;
    }

    _chatNotifSubscription = FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('user_notifications')
        .where('isRead', isEqualTo: false)
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .listen(
      (snapshot) {
        if (!_initialChatLoadDone) {
          // First snapshot: mark all existing IDs as already seen
          // so we don't fire local notifications for old messages.
          for (final doc in snapshot.docs) {
            _shownNotificationIds.add(doc.id);
          }
          _initialChatLoadDone = true;
          return;
        }

        // Subsequent snapshots: only show notifications for NEW docs
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added &&
              !_shownNotificationIds.contains(change.doc.id)) {
            _shownNotificationIds.add(change.doc.id);
            final data = change.doc.data();
            if (data != null) {
              _showLocalNotification(
                title: data['title'] as String? ?? 'New message',
                body: data['body'] as String? ?? '',
                chatId: data['chatId'] as String? ?? '',
              );
            }
          }
        }
      },
      onError: (error) {
        debugPrint(
            'NotificationProvider: Error listening to chat notifications: $error');
      },
    );
  }

  /// Show a local device notification for an incoming chat message.
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String chatId,
  }) async {
    if (!_localNotifInitialized) return;
    if (!PlatformHelper.isMobile) return;

    try {
      const androidDetails = AndroidNotificationDetails(
        'chat_messages',
        'Chat Messages',
        channelDescription: 'Notifications for new chat messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
        payload: jsonEncode({'chatId': chatId, 'action': 'open_chat'}),
      );
    } catch (e) {
      debugPrint('NotificationProvider: Error showing local notification: $e');
    }
  }

  // ── Mark as read ──────────────────────────────────────────────────

  /// Mark all unread activities as read (called when notification screen opens).
  Future<void> markAllActivitiesAsRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final unread = await FirebaseFirestore.instance
          .collection('activities')
          .where('recipientId', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .get();

      if (unread.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('NotificationProvider: Error marking activities as read: $e');
    }
  }

  /// Mark a single activity as read.
  Future<void> markActivityAsRead(String activityId) async {
    try {
      await FirebaseFirestore.instance
          .collection('activities')
          .doc(activityId)
          .update({'isRead': true});
    } catch (e) {
      debugPrint('NotificationProvider: Error marking activity as read: $e');
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────

  void _clearData() {
    _connectionsSubscription?.cancel();
    _connectionsSubscription = null;
    _activitiesSubscription?.cancel();
    _activitiesSubscription = null;
    _chatNotifSubscription?.cancel();
    _chatNotifSubscription = null;
    _pendingRequestCount = 0;
    _unreadActivityCount = 0;
    _activities = [];
    _shownNotificationIds.clear();
    _initialChatLoadDone = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectionsSubscription?.cancel();
    _activitiesSubscription?.cancel();
    _chatNotifSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
