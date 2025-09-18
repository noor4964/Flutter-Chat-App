import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';

class EnhancedNotificationService {
  bool _notificationsEnabled = true;
  bool _soundsEnabled = true;
  bool _vibrationEnabled = true;
  bool _groupNotifications = true;
  String _notificationTone = 'default';
  
  // Notification grouping
  final Map<String, List<Map<String, dynamic>>> _pendingNotifications = {};
  final Map<String, int> _chatNotificationCounts = {};
  
  // Local notifications plugin
  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();
  
  // Audio player for custom sounds
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Stream controller for notification clicks
  final navigatorKey = GlobalKey<NavigatorState>();

  // Callback for handling notification data
  void Function(Map<String, dynamic>)? onNotificationDataReceived;

  // Create a singleton instance
  static final EnhancedNotificationService _instance = EnhancedNotificationService._internal();

  // Private constructor
  EnhancedNotificationService._internal();

  // Factory constructor to return the singleton instance
  factory EnhancedNotificationService() {
    return _instance;
  }

  // Get notification settings
  bool get isNotificationsEnabled => _notificationsEnabled;
  bool get isSoundsEnabled => _soundsEnabled;
  bool get isVibrationEnabled => _vibrationEnabled;
  bool get isGroupNotificationsEnabled => _groupNotifications;
  String get notificationTone => _notificationTone;

  // Initialize notifications - enhanced for WhatsApp-like experience
  Future<void> initialize() async {
    try {
      // Skip initialization for unsupported platforms
      if (!PlatformHelper.isIOS && !PlatformHelper.isAndroid) {
        print('ℹ️ Skipping notification service initialization on unsupported platform');
        return;
      }

      print('🔔 Initializing enhanced notification service...');

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Request permission for notifications
      await _requestPermissions();

      // Set up Firebase Messaging handlers
      await _setupFirebaseMessaging();

      // Save FCM token to database
      await saveTokenToDatabase();

      // Load user notification preferences
      await _loadUserPreferences();

      // Setup background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      print('✅ Enhanced notification service initialized successfully');
    } catch (e) {
      print('❌ Error initializing notification service: $e');
    }
  }

  // Initialize local notifications for custom handling
  Future<void> _initializeLocalNotifications() async {
    // Android initialization settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    if (PlatformHelper.isAndroid) {
      await _createNotificationChannels();
    }
  }

  // Create notification channels for different types
  Future<void> _createNotificationChannels() async {
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Messages channel
      final messageVibrationPattern = Int64List.fromList([0, 250, 250, 250]);
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          'messages',
          'Messages',
          description: 'Notifications for new messages',
          importance: Importance.high,
          sound: const RawResourceAndroidNotificationSound('message_tone'),
          enableVibration: true,
          vibrationPattern: messageVibrationPattern,
        ),
      );

      // Calls channel
      final callVibrationPattern = Int64List.fromList([0, 1000, 500, 1000]);
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          'calls',
          'Calls',
          description: 'Notifications for incoming calls',
          importance: Importance.max,
          sound: const RawResourceAndroidNotificationSound('call_tone'),
          enableVibration: true,
          vibrationPattern: callVibrationPattern,
        ),
      );

      // Groups channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'groups',
          'Group Messages',
          description: 'Notifications for group messages',
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound('group_tone'),
          enableVibration: true,
        ),
      );
    }
  }

  // Enhanced Firebase messaging setup with WhatsApp-like features
  Future<void> _setupFirebaseMessaging() async {
    try {
      if (!PlatformHelper.isMobile) return;

      // Handle foreground messages with custom display
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        print('🔔 Got a message in foreground!');
        await _handleForegroundMessage(message);
      });

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('🔔 Notification tapped - app opened from background');
        _handleNotificationTap(message.data);
      });

      // Handle initial message if app was opened from terminated state
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        print('🔔 App opened from terminated state via notification');
        _handleNotificationTap(initialMessage.data);
      }

    } catch (e) {
      print('❌ Error setting up Firebase messaging handlers: $e');
    }
  }

  // Handle foreground messages with WhatsApp-like behavior
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final chatId = data['chatId'] ?? '';
    final type = data['type'] ?? '';

    // Check if user is currently viewing this chat
    // For now, we'll always show notifications in foreground
    // This can be enhanced with proper route checking later
    bool isViewingThisChat = false; // You'll need to implement this check

    if (!isViewingThisChat) {
      // Show custom notification with WhatsApp-like features
      await _showCustomNotification(message);
      
      // Play notification sound if enabled
      if (_soundsEnabled) {
        await _playNotificationSound(type);
      }

      // Vibrate if enabled
      if (_vibrationEnabled) {
        await _vibrate(type);
      }

      // Update badge count
      await _updateBadgeCount(chatId);
    }

    // Always handle the notification data
    if (onNotificationDataReceived != null) {
      onNotificationDataReceived!(data);
    }
  }

  // Show custom notification with grouping like WhatsApp
  Future<void> _showCustomNotification(RemoteMessage message) async {
    final data = message.data;
    final chatId = data['chatId'] ?? '';
    final senderName = data['senderName'] ?? 'Someone';
    final messageText = message.notification?.body ?? '';
    final type = data['type'] ?? 'message';

    if (_groupNotifications && chatId.isNotEmpty) {
      // Add to pending notifications for this chat
      _pendingNotifications.putIfAbsent(chatId, () => []);
      _pendingNotifications[chatId]!.add({
        'senderName': senderName,
        'message': messageText,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'type': type,
      });

      // Update count
      _chatNotificationCounts[chatId] = (_chatNotificationCounts[chatId] ?? 0) + 1;

      // Show grouped notification
      await _showGroupedNotification(chatId);
    } else {
      // Show individual notification
      await _showIndividualNotification(message);
    }
  }

  // Show grouped notification like WhatsApp
  Future<void> _showGroupedNotification(String chatId) async {
    final notifications = _pendingNotifications[chatId] ?? [];
    final count = _chatNotificationCounts[chatId] ?? 0;
    
    if (notifications.isEmpty) return;

    final latestNotification = notifications.last;
    final senderName = latestNotification['senderName'];
    
    String title;
    String body;
    
    if (count == 1) {
      title = senderName;
      body = latestNotification['message'];
    } else {
      title = senderName;
      body = '$count new messages';
    }

    // Create inbox style for Android
    final androidDetails = AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'Chat messages',
      importance: Importance.high,
      priority: Priority.high,
      groupKey: chatId,
      setAsGroupSummary: false,
      styleInformation: InboxStyleInformation(
        notifications.map((n) => '${n['senderName']}: ${n['message']}').toList(),
        contentTitle: '$count new messages',
        summaryText: 'Chat',
      ),
      actions: [
        const AndroidNotificationAction(
          'reply',
          'Reply',
          icon: DrawableResourceAndroidBitmap('ic_reply'),
          inputs: [
            AndroidNotificationActionInput(
              label: 'Type a message...',
            ),
          ],
        ),
        const AndroidNotificationAction(
          'mark_read',
          'Mark as read',
          icon: DrawableResourceAndroidBitmap('ic_check'),
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: 'messageCategory',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      chatId.hashCode,
      title,
      body,
      details,
      payload: jsonEncode({'chatId': chatId, 'action': 'open_chat'}),
    );
  }

  // Show individual notification
  Future<void> _showIndividualNotification(RemoteMessage message) async {
    final data = message.data;
    final chatId = data['chatId'] ?? '';
    final title = message.notification?.title ?? 'New Message';
    final body = message.notification?.body ?? '';

    const androidDetails = AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'Chat messages',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          'reply',
          'Reply',
          inputs: [
            AndroidNotificationActionInput(
              label: 'Type a message...',
            ),
          ],
        ),
        AndroidNotificationAction(
          'mark_read',
          'Mark as read',
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: 'messageCategory',
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
  }

  // Play notification sound based on type
  Future<void> _playNotificationSound(String type) async {
    try {
      String soundFile;
      switch (type) {
        case 'call':
          soundFile = 'sounds/call_tone.mp3';
          break;
        case 'group':
          soundFile = 'sounds/group_tone.mp3';
          break;
        default:
          soundFile = 'sounds/message_tone.mp3';
      }

      await _audioPlayer.play(AssetSource(soundFile));
    } catch (e) {
      print('Error playing notification sound: $e');
    }
  }

  // Vibrate based on notification type
  Future<void> _vibrate(String type) async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        switch (type) {
          case 'call':
            await Vibration.vibrate(pattern: [0, 1000, 500, 1000], repeat: 2);
            break;
          case 'group':
            await Vibration.vibrate(pattern: [0, 200, 100, 200]);
            break;
          default:
            await Vibration.vibrate(pattern: [0, 250, 250, 250]);
        }
      }
    } catch (e) {
      print('Error vibrating: $e');
    }
  }

  // Update badge count
  Future<void> _updateBadgeCount(String chatId) async {
    try {
      // Implementation depends on your badge plugin
      // For iOS, you can use flutter_app_badger
    } catch (e) {
      print('Error updating badge count: $e');
    }
  }

  // Handle notification taps
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      final data = jsonDecode(payload);
      _handleNotificationTap(data);
    }

    // Handle notification actions
    if (response.actionId != null) {
      _handleNotificationAction(response);
    }
  }

  // Handle notification actions (Reply, Mark as read, etc.)
  void _handleNotificationAction(NotificationResponse response) {
    switch (response.actionId) {
      case 'reply':
        // Handle inline reply
        final input = response.input;
        if (input != null && response.payload != null) {
          final data = jsonDecode(response.payload!);
          _handleInlineReply(data['chatId'], input);
        }
        break;
      case 'mark_read':
        // Mark as read
        if (response.payload != null) {
          final data = jsonDecode(response.payload!);
          _markChatAsRead(data['chatId']);
        }
        break;
    }
  }

  // Handle inline reply
  Future<void> _handleInlineReply(String chatId, String message) async {
    try {
      // Send message using your chat service
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // You'll need to inject your ChatService here
        // await chatService.sendMessage(chatId, message, user.uid);
        
        // Clear notifications for this chat
        await _clearChatNotifications(chatId);
      }
    } catch (e) {
      print('Error sending inline reply: $e');
    }
  }

  // Mark chat as read from notification
  Future<void> _markChatAsRead(String chatId) async {
    try {
      // Clear notifications for this chat
      await _clearChatNotifications(chatId);
      
      // Mark messages as read using your service
      // await chatService.markMessagesAsRead(chatId, currentUserId);
    } catch (e) {
      print('Error marking chat as read: $e');
    }
  }

  // Clear notifications for a specific chat
  Future<void> _clearChatNotifications(String chatId) async {
    // Remove from pending notifications
    _pendingNotifications.remove(chatId);
    _chatNotificationCounts.remove(chatId);
    
    // Cancel local notifications for this chat
    await _localNotifications.cancel(chatId.hashCode);
  }

  // Handle notification tap navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final chatId = data['chatId'];
    final action = data['action'] ?? 'open_chat';

    switch (action) {
      case 'open_chat':
        if (chatId != null) {
          // Navigate to chat screen
          // You'll need to implement navigation logic here
          navigatorKey.currentState?.pushNamed('/chat', arguments: {'chatId': chatId});
        }
        break;
      // Add more actions as needed
    }

    if (onNotificationDataReceived != null) {
      onNotificationDataReceived!(data);
    }
  }

  // Test notification with enhanced features
  Future<Map<String, dynamic>> sendTestNotification() async {
    try {
      // Check if we're on a supported platform
      if (!PlatformHelper.isIOS && !PlatformHelper.isAndroid) {
        return {
          'success': false,
          'message': 'Test notifications only supported on iOS and Android'
        };
      }

      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not logged in'};
      }

      // Send a local test notification
      await _localNotifications.show(
        999999,
        'Test Notification',
        'This is a test notification with WhatsApp-like features!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            importance: Importance.high,
            priority: Priority.high,
            actions: [
              AndroidNotificationAction('reply', 'Reply'),
              AndroidNotificationAction('test', 'Test Action'),
            ],
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode({'type': 'test', 'action': 'test'}),
      );

      return {
        'success': true,
        'message': 'Test notification sent successfully',
      };
    } catch (e) {
      print('❌ Error sending test notification: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  // Load user preferences
  Future<void> _loadUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _soundsEnabled = prefs.getBool('sounds_enabled') ?? true;
      _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      _groupNotifications = prefs.getBool('group_notifications') ?? true;
      _notificationTone = prefs.getString('notification_tone') ?? 'default';
    } catch (e) {
      print('❌ Error loading notification preferences: $e');
    }
  }

  // Save user preferences
  Future<void> _saveUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', _notificationsEnabled);
      await prefs.setBool('sounds_enabled', _soundsEnabled);
      await prefs.setBool('vibration_enabled', _vibrationEnabled);
      await prefs.setBool('group_notifications', _groupNotifications);
      await prefs.setString('notification_tone', _notificationTone);
    } catch (e) {
      print('❌ Error saving notification preferences: $e');
    }
  }

  // Set notification preferences
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    await _saveUserPreferences();
  }

  Future<void> setSoundsEnabled(bool enabled) async {
    _soundsEnabled = enabled;
    await _saveUserPreferences();
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    _vibrationEnabled = enabled;
    await _saveUserPreferences();
  }

  Future<void> setGroupNotifications(bool enabled) async {
    _groupNotifications = enabled;
    await _saveUserPreferences();
  }

  Future<void> setNotificationTone(String tone) async {
    _notificationTone = tone;
    await _saveUserPreferences();
  }

  // Request permissions
  Future<void> _requestPermissions() async {
    try {
      if (!PlatformHelper.isMobile) return;

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('🔔 Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      print('❌ Error requesting notification permissions: $e');
    }
  }

  // Save FCM token to database
  Future<void> saveTokenToDatabase() async {
    try {
      if (!PlatformHelper.isMobile) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });

      print('✅ Saved FCM token to database');
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  // Send push notification (Client-side implementation)
  Future<void> sendPushNotification({
    required String body,
    required String recipientId,
    required String chatId,
    String? title,
    Map<String, dynamic>? data,
  }) async {
    if (!_notificationsEnabled) return;

    try {
      // Get the recipient's FCM tokens from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(recipientId)
          .get();

      if (!userDoc.exists) {
        print('❌ Recipient user not found');
        return;
      }

      final userData = userDoc.data();
      final fcmTokens = userData?['fcmTokens'] as List<dynamic>?;

      if (fcmTokens == null || fcmTokens.isEmpty) {
        print('❌ No FCM tokens found for recipient');
        return;
      }

      // Store notification in Firestore for the recipient to display locally
      // This is a workaround since we can't use Firebase Functions (requires paid plan)
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(recipientId)
          .collection('user_notifications')
          .add({
        'senderId': FirebaseAuth.instance.currentUser?.uid ?? '',
        'recipientId': recipientId,
        'title': title ?? 'New message',
        'body': body,
        'chatId': chatId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'chat_message',
        'isRead': false,
        'data': {
          'chatId': chatId,
          'withSound': _soundsEnabled,
          'withVibration': _vibrationEnabled,
          ...?data,
        },
      });

      print('✅ Notification stored in Firestore for recipient: $recipientId');

      // Note: Without Firebase Functions (requires paid plan), we cannot send
      // direct FCM push notifications. The recipient will receive notifications
      // when they open the app and check for new messages.
      
    } catch (e) {
      print('❌ Error storing notification: $e');
    }
  }
}

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('🔔 Handling background message: ${message.messageId}');
  
  // Handle background notification processing
  // This runs even when the app is terminated
}