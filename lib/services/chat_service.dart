import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/models/message_model.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get Firestore instance
  FirebaseFirestore get firestore => _firestore;

  // Send a message
  Future<void> sendMessage(String chatId, String userId, String message) async {
    try {
      await _firestore.collection('chats').doc(chatId).collection('messages').add({
        'sender': userId,
        'text': message,
        'timestamp': FieldValue.serverTimestamp(),
        'readBy': [],
      });
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': message,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String chatId, String userId) async {
    try {
      QuerySnapshot messagesSnapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('readBy', arrayContains: userId)
          .get();

      for (var doc in messagesSnapshot.docs) {
        await doc.reference.update({
          'readBy': FieldValue.arrayUnion([userId]),
        });
      }
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Get messages stream
  Stream<List<Message>> getMessages(String chatId, String currentUserId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>?; // Ensure data is not null
              if (data != null) {
                return Message.fromJson(data, currentUserId);
              } else {
                throw Exception('Message data is null');
              }
            }).toList());
  }

  // Get username
  Future<String?> getUsername(String userId) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?; // Ensure data is not null
        return data?['username'];
      }
    } catch (e) {
      print('Error fetching username: $e');
    }
    return null;
  }

  // Get existing chat ID
  Future<String?> getExistingChatId(String currentUserId, String otherUserId) async {
    try {
      QuerySnapshot chatSnapshot = await _firestore
          .collection('chats')
          .where('userIds', arrayContains: currentUserId)
          .get();

      for (var doc in chatSnapshot.docs) {
        List<dynamic> userIds = doc['userIds'];
        if (userIds.contains(otherUserId)) {
          return doc.id;
        }
      }
    } catch (e) {
      print('Error fetching existing chat ID: $e');
    }
    return null;
  }

  // Create a new chat
  Future<String?> createChat(List<String> userIds, String chatName) async {
    try {
      DocumentReference chatRef = await _firestore.collection('chats').add({
        'userIds': userIds,
        'name': chatName,
        'lastMessage': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return chatRef.id;
    } catch (e) {
      print('Error creating chat: $e');
      return null;
    }
  }
}