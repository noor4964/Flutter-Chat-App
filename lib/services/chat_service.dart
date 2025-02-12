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
        .map((snapshot) => snapshot.docs
            .map((doc) => Chat.fromFirestore(doc))
            .toList());
  }

  // Delete a chat and remove the user from the logged user's database
  Future<void> deleteChat(String chatId, String userId) async {
    try {
      // Delete the chat
      await _firestore.collection('chats').doc(chatId).delete();

      // Remove the user from the logged user's database
      await _firestore.collection('users').doc(userId).delete();
    } catch (e) {
      print('Error deleting chat: $e');
    }
  }

  // Block a user
  Future<void> blockUser(String chatId, String userId) async {
    try {
      await _firestore.collection('chats').doc(chatId).update({
        'blockedUsers': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      print('Error blocking user: $e');
    }
  }

  // Unblock a user
  Future<void> unblockUser(String chatId, String userId) async {
    try {
      await _firestore.collection('chats').doc(chatId).update({
        'blockedUsers': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      print('Error unblocking user: $e');
    }
  }

  // Check if a user is blocked
  Future<bool> isUserBlocked(String chatId, String userId) async {
    try {
      DocumentSnapshot chatDoc = await _firestore.collection('chats').doc(chatId).get();
      List<dynamic> blockedUsers = chatDoc['blockedUsers'] ?? [];
      return blockedUsers.contains(userId);
    } catch (e) {
      print('Error checking if user is blocked: $e');
      return false;
    }
  }

  // Mute a user
  Future<void> muteUser(String chatId, String userId, DateTime until) async {
    try {
      await _firestore.collection('chats').doc(chatId).update({
        'mutedUsers.$userId': until,
      });
    } catch (e) {
      print('Error muting user: $e');
    }
  }

  // Unmute a user
  Future<void> unmuteUser(String chatId, String userId) async {
    try {
      await _firestore.collection('chats').doc(chatId).update({
        'mutedUsers.$userId': FieldValue.delete(),
      });
    } catch (e) {
      print('Error unmuting user: $e');
    }
  }

  // Check if a user is muted
  Future<bool> isUserMuted(String chatId, String userId) async {
    try {
      DocumentSnapshot chatDoc = await _firestore.collection('chats').doc(chatId).get();
      Map<String, dynamic> mutedUsers = chatDoc['mutedUsers'] ?? {};
      if (mutedUsers.containsKey(userId)) {
        DateTime muteUntil = (mutedUsers[userId] as Timestamp).toDate();
        if (muteUntil.isAfter(DateTime.now())) {
          return true;
        } else {
          await unmuteUser(chatId, userId);
          return false;
        }
      }
      return false;
    } catch (e) {
      print('Error checking if user is muted: $e');
      return false;
    }
  }

  // Get username by user ID
  Future<String?> getUsername(String userId) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      return userDoc['username'];
    } catch (e) {
      print('Error getting username: $e');
      return null;
    }
  }

  // Check for existing chat between two users
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
      print('Error checking for existing chat: $e');
      return null;
    }
  }
}