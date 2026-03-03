import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';
import 'package:flutter_chat_app/services/settings_service.dart';

class PresenceService {
  static final PresenceService _instance = PresenceService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SettingsService _settingsService = SettingsService();

  bool _appearOffline = false;

  // Flag to check if we're on Windows with Firebase disabled
  bool get _isWindowsWithoutFirebase =>
      PlatformHelper.isWindows && !FirebaseConfig.isFirebaseEnabledOnWindows;

  bool get appearOffline => _appearOffline;

  factory PresenceService() {
    return _instance;
  }

  PresenceService._internal() {
    _loadAppearOffline();
  }

  Future<void> _loadAppearOffline() async {
    _appearOffline = await _settingsService.isAppearOffline();
  }

  /// Toggle appear-offline mode. When enabled, goOnline() becomes a no-op
  /// and the user is immediately set to offline in Firestore.
  Future<void> setAppearOffline(bool enabled) async {
    _appearOffline = enabled;
    await _settingsService.setAppearOffline(enabled);
    if (enabled) {
      await _forceGoOffline();
    } else {
      await _forceGoOnline();
    }
  }

  // Set user as online (respects appear-offline)
  Future<void> goOnline() async {
    if (_appearOffline) return; // No-op when invisible
    await _forceGoOnline();
  }

  // Set user as offline
  Future<void> goOffline() async {
    await _forceGoOffline();
    await clearActiveChat();
  }

  Future<void> _forceGoOnline() async {
    await updateOnlineStatus(true);
  }

  Future<void> _forceGoOffline() async {
    await updateOnlineStatus(false);
  }

  // Update the user's online status
  Future<void> updateOnlineStatus(bool isOnline) async {
    if (_isWindowsWithoutFirebase) return;

    final String? userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore.collection('users').doc(userId).update({
        'isOnline': isOnline,
        'lastActive': FieldValue.serverTimestamp(),
      });

      print('Updated online status: $isOnline for user: $userId');
    } catch (e) {
      print('Error updating online status: $e');
    }
  }

  // Set the chat ID that the user is currently viewing
  Future<void> setActiveChat(String chatId) async {
    if (_isWindowsWithoutFirebase) return;

    final String? userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore.collection('users').doc(userId).update({
        'activeChat': chatId,
        'activeChatTimestamp': FieldValue.serverTimestamp(),
      });

      print('User $userId is now viewing chat: $chatId');
    } catch (e) {
      print('Error setting active chat: $e');
    }
  }

  // Clear the active chat when user leaves the chat screen
  Future<void> clearActiveChat() async {
    if (_isWindowsWithoutFirebase) return;

    final String? userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore.collection('users').doc(userId).update({
        'activeChat': '',
        'activeChatTimestamp': FieldValue.serverTimestamp(),
      });

      print('User $userId is no longer viewing any chat');
    } catch (e) {
      print('Error clearing active chat: $e');
    }
  }

  // Check if a user is actively viewing a specific chat
  Future<bool> isUserActiveInChat(String userId, String chatId) async {
    if (_isWindowsWithoutFirebase) return false;

    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data();

      if (userData == null) return false;

      final String activeChat = userData['activeChat'] ?? '';

      // Check if the user is online and viewing this specific chat
      return userData['isOnline'] == true && activeChat == chatId;
    } catch (e) {
      print('Error checking if user is in chat: $e');
      return false;
    }
  }

  // Stream of online status changes for a specific user
  Stream<bool> getUserOnlineStatusStream(String userId) {
    if (_isWindowsWithoutFirebase) {
      // Return a fake stream for Windows
      return Stream.value(true);
    }

    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return false;

      final data = snapshot.data();
      if (data == null) return false;

      return data['isOnline'] == true;
    }).handleError((error) {
      print('Error in online status stream: $error');
      return false;
    });
  }

  // Get a stream of active users from a list of user IDs
  Stream<List<String>> getActiveUsersStream(List<String> userIds) {
    if (_isWindowsWithoutFirebase) {
      // Return an empty stream for Windows
      return Stream.value([]);
    }

    if (userIds.isEmpty) return Stream.value([]);

    // Filter out empty strings to avoid Firestore query errors
    final validUserIds = userIds.where((id) => id.isNotEmpty).toList();
    if (validUserIds.isEmpty) return Stream.value([]);

    return _firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: validUserIds)
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc.id).toList();
    }).handleError((error) {
      print('Error in active users stream: $error');
      return <String>[];
    });
  }
}
