import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/notification_service.dart';

class ChatNotificationService {
  static final ChatNotificationService _instance =
      ChatNotificationService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();

  factory ChatNotificationService() {
    return _instance;
  }

  ChatNotificationService._internal();

  // Send a message notification to a recipient
  Future<void> sendMessageNotification({
    required String recipientId,
    required String senderId,
    required String senderName,
    required String message,
    required String chatId,
  }) async {
    try {
      // Get recipient's data
      final userDoc =
          await _firestore.collection('users').doc(recipientId).get();
      final userData = userDoc.data();

      if (userData == null) {
        print('User $recipientId not found or has no data');
        return;
      }

      // Store notification in Firestore for persistence
      await _saveNotification(
        recipientId: recipientId,
        senderId: senderId,
        senderName: senderName,
        message: message,
        chatId: chatId,
      );

      // Send FCM notification
      await _notificationService.sendPushNotification(
        title: senderName,
        body: message,
        recipientId: recipientId,
        chatId: chatId,
        data: {
          'type': 'chat_message',
          'senderId': senderId,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        },
      );
    } catch (e) {
      print('Error sending message notification: $e');
    }
  }

  // Store notification in Firestore
  Future<void> _saveNotification({
    required String recipientId,
    required String senderId,
    required String senderName,
    required String message,
    required String chatId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'recipientId': recipientId,
        'senderId': senderId,
        'senderName': senderName,
        'message': message,
        'chatId': chatId,
        'type': 'chat_message',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving notification: $e');
    }
  }

  // Mark all notifications for a specific chat as read
  Future<void> markChatNotificationsAsRead(String chatId) async {
    try {
      final String? currentUserId = _auth.currentUser?.uid;

      if (currentUserId == null) return;

      // Get all unread notifications for this chat and user
      final QuerySnapshot notificationsSnapshot = await _firestore
          .collection('notifications')
          .where('recipientId', isEqualTo: currentUserId)
          .where('chatId', isEqualTo: chatId)
          .where('isRead', isEqualTo: false)
          .get();

      // Create a batch update
      final batch = _firestore.batch();

      for (var doc in notificationsSnapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();

      print(
          'Marked ${notificationsSnapshot.docs.length} notifications as read for chat $chatId');
    } catch (e) {
      print('Error marking chat notifications as read: $e');
    }
  }

  // Get unread notifications count
  Future<int> getUnreadNotificationsCount() async {
    try {
      final String? currentUserId = _auth.currentUser?.uid;

      if (currentUserId == null) return 0;

      final QuerySnapshot notificationsSnapshot = await _firestore
          .collection('notifications')
          .where('recipientId', isEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      return notificationsSnapshot.docs.length;
    } catch (e) {
      print('Error getting unread notifications count: $e');
      return 0;
    }
  }

  // Delete all notifications for a user
  Future<void> clearAllNotifications() async {
    try {
      final String? currentUserId = _auth.currentUser?.uid;

      if (currentUserId == null) return;

      final QuerySnapshot notificationsSnapshot = await _firestore
          .collection('notifications')
          .where('recipientId', isEqualTo: currentUserId)
          .get();

      final batch = _firestore.batch();

      for (var doc in notificationsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      print('Cleared ${notificationsSnapshot.docs.length} notifications');
    } catch (e) {
      print('Error clearing notifications: $e');
    }
  }

  // Get chat notifications stream for UI updates
  Stream<QuerySnapshot> getChatNotificationsStream() {
    final String? currentUserId = _auth.currentUser?.uid;

    if (currentUserId == null) {
      // Return an empty stream when no user is logged in
      return Stream.empty();
    }

    return _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: currentUserId)
        .where('type', isEqualTo: 'chat_message')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
