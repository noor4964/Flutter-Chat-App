import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_chat_app/services/settings_service.dart';

class NotificationService {
  static const String _notificationsEnabledKey = 'notifications_enabled';
  final SettingsService _settingsService = SettingsService();

  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  // Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    return await _settingsService.areNotificationsEnabled();
  }

  // Set notification preference
  Future<void> setNotificationsEnabled(bool enabled) async {
    await _settingsService.setNotificationsEnabled(enabled);
  }

  // Check if sounds are enabled
  Future<bool> areSoundsEnabled() async {
    return await _settingsService.isSoundEnabled();
  }

  // Set sound preference
  Future<void> setSoundsEnabled(bool enabled) async {
    await _settingsService.setSoundEnabled(enabled);
  }

  // Handle new message notification
  Future<void> showNewMessageNotification({
    required String senderId,
    required String senderName,
    required String message,
  }) async {
    final notificationsEnabled = await areNotificationsEnabled();

    if (!notificationsEnabled) {
      print('Notifications are disabled - not showing notification');
      return;
    }

    // Check if sounds should be played
    final soundsEnabled = await areSoundsEnabled();

    // Here you would integrate with a platform-specific notification system
    // For example, Firebase Cloud Messaging, flutter_local_notifications, etc.
    // You would also play a sound if soundsEnabled is true

    print(
        'NOTIFICATION: New message from $senderName: $message (Sound: ${soundsEnabled ? "On" : "Off"})');
  }

  // Handle connection request notification
  Future<void> showConnectionRequestNotification({
    required String senderId,
    required String senderName,
  }) async {
    final notificationsEnabled = await areNotificationsEnabled();

    if (!notificationsEnabled) {
      print('Notifications are disabled - not showing notification');
      return;
    }

    // Check if sounds should be played
    final soundsEnabled = await areSoundsEnabled();

    // Platform-specific notification code would go here
    // You would also play a sound if soundsEnabled is true

    print(
        'NOTIFICATION: New connection request from $senderName (Sound: ${soundsEnabled ? "On" : "Off"})');
  }
}
