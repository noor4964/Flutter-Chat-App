import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:cloud_functions/cloud_functions.dart';

class NotificationService {
  bool _notificationsEnabled = true;
  bool _soundsEnabled = true;

  // Stream controller for notification clicks
  final navigatorKey = GlobalKey<NavigatorState>();

  // Callback for handling notification data
  void Function(Map<String, dynamic>)? onNotificationDataReceived;

  // Create a singleton instance
  static final NotificationService _instance = NotificationService._internal();

  // Private constructor
  NotificationService._internal();

  // Factory constructor to return the singleton instance
  factory NotificationService() {
    return _instance;
  }

  // Get notification settings
  bool get isNotificationsEnabled => _notificationsEnabled;
  bool get isSoundsEnabled => _soundsEnabled;

  // Test notification function to validate notifications are working
  Future<Map<String, dynamic>> sendTestNotification() async {
    try {
      // Check if we're on a supported platform
      if (!PlatformHelper.isIOS && !PlatformHelper.isAndroid) {
        print('⚠️ Test notification skipped: unsupported platform');
        return {
          'success': false,
          'message': 'Test notifications only supported on iOS and Android'
        };
      }

      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ Test notification skipped: user not logged in');
        return {'success': false, 'message': 'User not logged in'};
      }

      // Get the FCM token to verify it exists
      final token = await FirebaseMessaging.instance.getToken();
      print('📱 Device FCM token: ${token?.substring(0, 10)}...');

      if (token == null || token.isEmpty) {
        print('❌ Test notification failed: No FCM token available');
        return {'success': false, 'message': 'No FCM token available'};
      }

      // Send a notification to the current user using Cloud Functions
      final functions = FirebaseFunctions.instance;
      final result =
          await functions.httpsCallable('sendTestNotification').call({
        'userId': user.uid,
        'withSound': _soundsEnabled,
      });

      print('✅ Test notification sent successfully');
      print('📝 Response data: ${result.data}');

      return {
        'success': true,
        'message': 'Test notification sent successfully',
        'token': token.substring(0, 10) + '...',
        'response': result.data
      };
    } catch (e) {
      print('❌ Error sending test notification: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  // Set notification settings
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    // Save setting to persistent storage or user preferences
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'notificationsEnabled': enabled});
      }
    } catch (e) {
      print('❌ Error saving notification setting: $e');
    }
  }

  Future<void> setSoundsEnabled(bool enabled) async {
    _soundsEnabled = enabled;
    // Save setting to persistent storage or user preferences
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'notificationSoundsEnabled': enabled});
      }
    } catch (e) {
      print('❌ Error saving notification sound setting: $e');
    }
  }

  // Initialize notifications - safe for all platforms
  Future<void> initialize() async {
    try {
      // Skip initialization for unsupported platforms
      if (!PlatformHelper.isIOS && !PlatformHelper.isAndroid) {
        print(
            'ℹ️ Skipping notification service initialization on unsupported platform');
        return;
      }

      print('🔔 Initializing notification service...');

      // Request permission for notifications
      await _requestPermissions();

      // Set up Firebase Messaging handlers
      await _setupFirebaseMessaging();

      // Save FCM token to database
      await saveTokenToDatabase();

      // Load user notification preferences
      await _loadUserPreferences();

      print('✅ Notification service initialized successfully');
    } catch (e) {
      print('❌ Error initializing notification service: $e');
    }
  }

  // Load user notification preferences from Firestore
  Future<void> _loadUserPreferences() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userData = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userData.exists) {
          _notificationsEnabled =
              userData.data()?['notificationsEnabled'] ?? true;
          _soundsEnabled =
              userData.data()?['notificationSoundsEnabled'] ?? true;
        }
      }
    } catch (e) {
      print('❌ Error loading notification preferences: $e');
    }
  }

  // Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      if (!PlatformHelper.isMobile) return;

      // Request permission from Firebase Messaging
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print(
          '🔔 Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      print('❌ Error requesting notification permissions: $e');
    }
  }

  // Set up Firebase messaging handlers
  Future<void> _setupFirebaseMessaging() async {
    try {
      if (!PlatformHelper.isMobile) return;

      // Set up foreground message handler
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('🔔 Got a message in foreground!');
        print('🔔 Message data: ${message.data}');

        if (message.notification != null) {
          print('🔔 Message notification: ${message.notification!.title}');
        }

        // Handle the notification data
        if (onNotificationDataReceived != null) {
          onNotificationDataReceived!(message.data);
        }
      });
    } catch (e) {
      print('❌ Error setting up Firebase messaging handlers: $e');
    }
  }

  // Send a push notification
  Future<void> sendPushNotification({
    required String body,
    required String recipientId,
    required String chatId,
    String? title,
    Map<String, dynamic>? data,
  }) async {
    // Skip if notifications are disabled
    if (!_notificationsEnabled) return;

    try {
      // Get Firebase Functions instance
      final functions = FirebaseFunctions.instance;

      // Call the sendChatNotification function
      final result =
          await functions.httpsCallable('sendChatNotification').call({
        'message': body,
        'title': title ?? 'New message',
        'recipientId': recipientId,
        'chatId': chatId,
        'withSound': _soundsEnabled,
        ...?data,
      });

      print('Push notification sent successfully: ${result.data}');
    } catch (e) {
      print('Error sending push notification: $e');
    }
  }

  // Save FCM token to database
  Future<void> saveTokenToDatabase() async {
    try {
      if (!PlatformHelper.isMobile) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('ℹ️ No signed-in user, skipping FCM token save');
        return;
      }

      // Get the token
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        print('❌ Failed to get FCM token');
        return;
      }

      // Save it to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });

      print('✅ Saved FCM token to database: ${token.substring(0, 10)}...');
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }
}
