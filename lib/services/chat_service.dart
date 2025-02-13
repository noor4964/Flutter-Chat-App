import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/models/chat_model.dart';
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
      });
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': message,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error sending message: $e');
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
        .map((snapshot) => snapshot.docs.map((doc) => Message.fromJson(doc.data(), currentUserId)).toList());
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

  // Get user chats
  Stream<List<Chat>> getUserChats(String userId) {
    return _firestore
        .collection('chats')
        .where('userIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Chat.fromFirestore(doc)).toList());
  }

  // Accept connection request
  Future<void> acceptConnectionRequest(String requestId, String senderId) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("❌ User not logged in!");
      return;
    }

    try {
      await _firestore.runTransaction((transaction) async {
        DocumentReference connectionRef = _firestore.collection('connections').doc(requestId);
        DocumentSnapshot connectionDoc = await transaction.get(connectionRef);

        if (connectionDoc.exists) {
          transaction.update(connectionRef, {'status': 'accepted'});

          // Create a chat document for both users
          DocumentReference chatRef = _firestore.collection('chats').doc();
          transaction.set(chatRef, {
            'userIds': [user.uid, senderId],
            'createdAt': FieldValue.serverTimestamp(),
          });

          print("✅ Connection accepted and chat created!");
        }
      });
    } catch (e) {
      print("❌ Error accepting connection: $e");
    }
  }

  // Delete a chat
  Future<void> deleteChat(String chatId, String userId) async {
    try {
      DocumentReference chatRef = _firestore.collection('chats').doc(chatId);
      DocumentSnapshot chatDoc = await chatRef.get();

      if (chatDoc.exists) {
        List<dynamic> userIds = chatDoc['userIds'];
        if (userIds.contains(userId)) {
          await chatRef.delete();
          print("✅ Chat deleted!");
        } else {
          print("❌ User not authorized to delete this chat!");
        }
      } else {
        print("❌ Chat does not exist!");
      }
    } catch (e) {
      print("❌ Error deleting chat: $e");
    }
  }

  // Get existing chat ID
  Future<String?> getExistingChatId(String userId1, String userId2) async {
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('chats')
          .where('userIds', arrayContains: userId1)
          .get();

      for (var doc in querySnapshot.docs) {
        List<dynamic> userIds = doc['userIds'];
        if (userIds.contains(userId2)) {
          return doc.id;
        }
      }
      return null;
    } catch (e) {
      print("❌ Error getting existing chat ID: $e");
      return null;
    }
  }

  // Get username
  Future<String?> getUsername(String userId) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        return userDoc['username'];
      }
      return null;
    } catch (e) {
      print("❌ Error getting username: $e");
      return null;
    }
  }
}