import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/models/message_model.dart';
import '../services/firebase_config.dart';
import 'package:flutter_chat_app/services/auth_service.dart';

class ChatService {
  // Expose auth service for Windows platform checks
  final AuthService authService = AuthService();

  // Flag to check if we're on Windows with Firebase disabled
  bool get _isWindowsWithoutFirebase =>
      PlatformHelper.isWindows && !FirebaseConfig.isFirebaseEnabledOnWindows;

  // Flag to check if we're on web
  bool get _isWeb => kIsWeb;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Send a text message
  Future<void> sendMessage(
      String chatId, String message, String senderId) async {
    if (_isWindowsWithoutFirebase) {
      print('Message sending skipped on Windows');
      return;
    }

    try {
      // Add debug logging
      print('Sending message on platform: ${_isWeb ? "Web" : "Native"}');
      print('ChatID: $chatId, SenderID: $senderId');

      // Verify chat exists
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) {
        print('Error: Chat with ID $chatId does not exist');
        throw Exception('Chat does not exist');
      }

      // Add message to chat collection
      DocumentReference messageRef = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'content': message,
        'senderId': senderId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'text',
        'readBy': [senderId], // Initialize with sender as having read it
      });

      print('Message document created with ID: ${messageRef.id}');

      // Use a try-catch block for the update operation to prevent failure cascade
      try {
        // Update chat metadata with last message
        await _firestore.collection('chats').doc(chatId).update({
          'lastMessage': message,
          'lastMessageSenderId': senderId,
          'lastMessageReadBy': [senderId],
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('Chat metadata updated successfully');
      } catch (e) {
        // Log but continue - we don't want to fail the whole message send if just metadata fails
        print('Warning: Failed to update chat metadata: $e');
      }

      // Clear typing indicator when sending a message
      try {
        await setTypingStatus(chatId, senderId, false);
      } catch (e) {
        // Log but continue - typing status is non-critical
        print('Warning: Failed to clear typing status: $e');
      }

      print('Message sent successfully to chat $chatId');
    } catch (e) {
      print('Error sending message: $e');
      // Added stack trace for better debugging
      print('Stack trace: ${StackTrace.current}');
      throw e;
    }
  }

  // Send an image message
  Future<void> sendImageMessage(
      String chatId, String imageUrl, String senderId) async {
    if (_isWindowsWithoutFirebase) {
      print('Image message sending skipped on Windows');
      return;
    }

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

      // Clear typing indicator when sending a message
      await setTypingStatus(chatId, senderId, false);
    } catch (e) {
      print('Error sending image message: $e');
      throw e;
    }
  }

  // Set typing status for a user in a chat
  Future<void> setTypingStatus(
      String chatId, String userId, bool isTyping) async {
    if (_isWindowsWithoutFirebase) return;

    try {
      // Update typing status in the typingUsers subcollection
      final typingRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('typingUsers')
          .doc(userId);

      if (isTyping) {
        await typingRef.set({
          'isTyping': true,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // If not typing, delete the document
        await typingRef.delete();
      }
    } catch (e) {
      print('Error updating typing status: $e');
    }
  }

  // Get typing status stream for a specific user in a chat
  Stream<bool> getTypingStatus(
      String chatId, String typingUserId, String currentUserId) {
    if (_isWindowsWithoutFirebase) return Stream.value(false);

    // Don't show typing indicator for the current user
    if (typingUserId == currentUserId) {
      return Stream.value(false);
    }

    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('typingUsers')
        .doc(typingUserId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        // Check if the timestamp is recent (within last 10 seconds)
        final data = snapshot.data();
        if (data != null && data['timestamp'] != null) {
          try {
            // Handle different timestamp formats safely
            DateTime timestampDate;
            if (data['timestamp'] is Timestamp) {
              timestampDate = (data['timestamp'] as Timestamp).toDate();
            } else if (data['timestamp'] is DateTime) {
              timestampDate = data['timestamp'] as DateTime;
            } else {
              // If timestamp is in an unexpected format, default to showing no typing
              print('Unexpected timestamp format: ${data['timestamp']}');
              return false;
            }

            final now = DateTime.now();
            final diff = now.difference(timestampDate).inSeconds;

            // Consider typing if timestamp is less than 10 seconds old
            return diff < 10 && data['isTyping'] == true;
          } catch (e) {
            // If there's any error processing the timestamp, don't show typing
            print('Error processing typing timestamp: $e');
            return false;
          }
        }
        // Safely access isTyping with null check
        return data != null && data['isTyping'] == true;
      }
      return false;
    }).handleError((error) {
      // Handle stream errors
      print('Error in typing status stream: $error');
      return false;
    });
  }

  // Mark a chat as read for the current user
  Future<void> markChatAsRead(String chatId, String userId) async {
    if (_isWindowsWithoutFirebase) return;

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
    if (_isWindowsWithoutFirebase) {
      // Return a dummy chat ID on Windows
      return 'windows-mock-chat-id';
    }

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
    if (_isWindowsWithoutFirebase) {
      // Return a dummy chat ID on Windows
      return 'windows-mock-chat-id-${DateTime.now().millisecondsSinceEpoch}';
    }

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
    if (_isWindowsWithoutFirebase) {
      // Return mock user details on Windows
      return {
        'uid': userId,
        'username': 'Windows User',
        'email': 'test@example.com',
        'isOnline': true,
      };
    }

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
    if (_isWindowsWithoutFirebase) {
      // Return mock username on Windows
      return 'Windows User';
    }

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
    if (_isWindowsWithoutFirebase) return;

    try {
      await markChatAsRead(chatId, userId);
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Get messages stream for a chat
  Stream<List<Message>> getMessages(String chatId, String currentUserId) {
    if (_isWindowsWithoutFirebase) {
      // Return empty messages list for Windows
      return Stream.value([]);
    }

    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        try {
          final data = doc.data();
          DateTime timestamp;

          // Safely handle the timestamp conversion
          if (data['timestamp'] is Timestamp) {
            timestamp = (data['timestamp'] as Timestamp).toDate();
          } else if (data['timestamp'] is DateTime) {
            timestamp = data['timestamp'] as DateTime;
          } else {
            // If timestamp is missing or in an unexpected format, use current time
            timestamp = DateTime.now();
          }

          // Safely handle the readBy field
          List<dynamic> readByList = [];
          if (data['readBy'] != null) {
            if (data['readBy'] is List) {
              readByList = data['readBy'];
            }
          }

          return Message(
            id: doc.id,
            sender: data['senderId'] ?? '',
            text: data['content'] ?? '',
            timestamp: timestamp,
            isMe: data['senderId'] == currentUserId,
            isRead: readByList.contains(currentUserId),
            type: data['type'] ?? 'text',
          );
        } catch (e) {
          // Log the error but return a default message to avoid breaking the UI
          print('Error processing message document ${doc.id}: $e');
          return Message(
            id: doc.id,
            sender: 'error',
            text: 'Error loading message',
            timestamp: DateTime.now(),
            isMe: false,
            isRead: false,
            type: 'text',
          );
        }
      }).toList();
    }).handleError((error) {
      // Handle stream errors
      print('Error in messages stream: $error');
      return <Message>[];
    });
  }
}
