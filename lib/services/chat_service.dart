import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/models/message_model.dart'; // Import Message model

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Send a text message
  Future<void> sendMessage(
      String chatId, String message, String senderId) async {
    try {
      // Add message to chat collection
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'content': message,
        'senderId': senderId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'text',
      });

      // Update chat metadata with last message
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': message,
        'lastMessageSenderId': senderId,
        'lastMessageReadBy': [senderId],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error sending message: $e');
      throw e;
    }
  }

  // Send an image message
  Future<void> sendImageMessage(
      String chatId, String imageUrl, String senderId) async {
    try {
      // Add image message to chat collection
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'content': imageUrl,
        'senderId': senderId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'image',
      });

      // Update chat metadata with indicator of image message
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': PlatformHelper.isDesktop ? '📷 Image' : '🖼️ Image',
        'lastMessageSenderId': senderId,
        'lastMessageReadBy': [senderId],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error sending image message: $e');
      throw e;
    }
  }

  // Mark a chat as read for the current user
  Future<void> markChatAsRead(String chatId, String userId) async {
    try {
      // Get the current chat
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      final chatData = chatDoc.data();

      if (chatData != null) {
        // Get current readers
        List<String> readBy =
            List<String>.from(chatData['lastMessageReadBy'] ?? []);

        // Check if the current user is not already in the list
        if (!readBy.contains(userId)) {
          readBy.add(userId);

          // Update the document with the new list
          await _firestore.collection('chats').doc(chatId).update({
            'lastMessageReadBy': readBy,
          });
        }
      }
    } catch (e) {
      print('Error marking chat as read: $e');
    }
  }

  // Get existing chat ID between two users
  Future<String?> getExistingChatId(
      String currentUserId, String otherUserId) async {
    try {
      final querySnapshot = await _firestore
          .collection('chats')
          .where('userIds', arrayContains: currentUserId)
          .get();

      for (var doc in querySnapshot.docs) {
        List<String> userIds = List<String>.from(doc.data()['userIds']);
        if (userIds.contains(otherUserId)) {
          return doc.id; // Chat already exists, return its ID
        }
      }

      return null; // No existing chat found
    } catch (e) {
      print('Error checking for existing chat: $e');
      return null;
    }
  }

  // Create a new chat with a list of user IDs and chat name
  Future<String?> createChat(List<String> userIds, String chatName) async {
    try {
      // Create a new chat
      final docRef = await _firestore.collection('chats').add({
        'userIds': userIds,
        'chatName': chatName,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageSenderId': '',
        'lastMessageReadBy': [],
      });

      return docRef.id;
    } catch (e) {
      print('Error creating chat: $e');
      return null;
    }
  }

  // Get user details by ID
  Future<Map<String, dynamic>?> getUserDetails(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      return userDoc.data();
    } catch (e) {
      print('Error getting user details: $e');
      return null;
    }
  }

  // Get username by user ID
  Future<String> getUsername(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data();
      return userData?['username'] ?? 'Unknown';
    } catch (e) {
      print('Error getting username: $e');
      return 'Unknown';
    }
  }

  // Mark all messages in a chat as read for the current user
  Future<void> markMessagesAsRead(String chatId, String userId) async {
    try {
      await markChatAsRead(chatId, userId);
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Get messages stream for a chat
  Stream<List<Message>> getMessages(String chatId, String currentUserId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Message(
          id: doc.id,
          sender: data['senderId'] ?? '',
          text: data['content'] ?? '',
          timestamp: data['timestamp'] != null
              ? (data['timestamp'] as Timestamp).toDate()
              : DateTime.now(),
          isMe: data['senderId'] == currentUserId,
          isRead: (data['readBy'] ?? []).contains(currentUserId),
        );
      }).toList();
    });
  }
}
