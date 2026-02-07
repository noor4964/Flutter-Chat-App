import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/models/message_model.dart';
import 'package:flutter_chat_app/models/message_reaction.dart';
import '../services/firebase_config.dart';
import 'package:flutter_chat_app/services/auth_service.dart';
import 'package:flutter_chat_app/services/chat_notification_service.dart';
import 'package:flutter_chat_app/services/enhanced_notification_service.dart';
import 'package:flutter_chat_app/services/presence_service.dart';
import 'dart:io';

class ChatService {
  // Expose auth service for Windows platform checks
  final AuthService authService = AuthService();

  // Flag to check if we're on Windows with Firebase disabled
  bool get _isWindowsWithoutFirebase =>
      PlatformHelper.isWindows && !FirebaseConfig.isFirebaseEnabledOnWindows;

  // Flag to check if we're on web
  bool get _isWeb => kIsWeb;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Send a text message - Optimized for performance
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

      // Create message data once
      final messageData = {
        'content': message,
        'senderId': senderId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'text',
        'readBy': [senderId], // Initialize with sender as having read it
      };

      // Create chat metadata update data
      final chatUpdateData = {
        'lastMessage': message,
        'lastMessageSenderId': senderId,
        'lastMessageReadBy': [senderId],
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Use batch write for atomic operations and better performance
      final batch = _firestore.batch();
      
      // Add message to chat collection
      final messageRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(); // Generate doc reference without await
      
      batch.set(messageRef, messageData);
      
      // Update chat metadata in the same batch
      final chatRef = _firestore.collection('chats').doc(chatId);
      batch.update(chatRef, chatUpdateData);

      // Execute batch write - this is much faster than sequential operations
      await batch.commit();
      
      print('Message and metadata saved successfully with batch write');

      // Perform non-critical operations asynchronously (don't await)
      _performAsyncCleanup(chatId, senderId, message);

      print('Message sent successfully to chat $chatId');
    } catch (e) {
      print('Error sending message: $e');
      // Added stack trace for better debugging
      print('Stack trace: ${StackTrace.current}');
      throw e;
    }
  }

  // Separate method for non-critical async operations
  Future<void> _performAsyncCleanup(String chatId, String senderId, String message) async {
    // These operations run in background and don't block the main send operation
    try {
      // Clear typing indicator when sending a message
      setTypingStatus(chatId, senderId, false).catchError((e) {
        print('Warning: Failed to clear typing status: $e');
      });

      // Send notification to chat recipients who aren't currently in the chat
      _sendNotificationToRecipients(chatId, senderId, message).catchError((e) {
        print('Warning: Failed to send notifications: $e');
      });
    } catch (e) {
      print('Warning: Background cleanup failed: $e');
    }
  }

  // Helper method to send notification to chat recipients - Enhanced for WhatsApp-like experience
  Future<void> _sendNotificationToRecipients(
      String chatId, String senderId, String message) async {
    try {
      // Get chat document to find all recipients
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      final chatData = chatDoc.data();

      if (chatData == null) return;

      // Get all user IDs in the chat
      final List<String> userIds = List<String>.from(chatData['userIds'] ?? []);

      // Get sender's username for the notification
      String senderName = await getUsername(senderId);

      // Check if it's a group chat
      bool isGroupChat = userIds.length > 2;

      // For each recipient (excluding sender)
      for (String userId in userIds) {
        if (userId != senderId) {
          // Check if recipient is currently active in this chat
          final presenceService = PresenceService();
          bool isActive =
              await presenceService.isUserActiveInChat(userId, chatId);

          // Only send notification if user is not actively viewing the chat
          if (!isActive) {
            // Use enhanced notification service for WhatsApp-like features
            final enhancedNotificationService = EnhancedNotificationService();
            await enhancedNotificationService.sendPushNotification(
              body: message,
              recipientId: userId,
              chatId: chatId,
              title: isGroupChat ? chatData['name'] ?? 'Group Chat' : senderName,
              data: {
                'senderId': senderId,
                'senderName': senderName,
                'messageType': 'text',
                'isGroupChat': isGroupChat.toString(),
                'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
              },
            );

            // Fallback to original notification service for compatibility
            final notificationService = ChatNotificationService();
            await notificationService.sendMessageNotification(
                recipientId: userId,
                senderId: senderId,
                senderName: senderName,
                message: message,
                chatId: chatId);

            print('Enhanced notification sent to $userId for message in chat $chatId');
          } else {
            print(
                'User $userId is active in chat $chatId, no notification sent');
          }
        }
      }
    } catch (e) {
      // Log but don't fail the message send process
      print('Error sending notification: $e');
    }
  }

  // Helper method to send notification for media messages (images, videos, files)
  Future<void> _sendMediaNotificationToRecipients(
      String chatId, String senderId, String mediaDescription, String mediaType) async {
    try {
      // Get chat document to find all recipients
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      final chatData = chatDoc.data();

      if (chatData == null) return;

      // Get all user IDs in the chat
      final List<String> userIds = List<String>.from(chatData['userIds'] ?? []);

      // Get sender's username for the notification
      String senderName = await getUsername(senderId);

      // Check if it's a group chat
      bool isGroupChat = userIds.length > 2;

      // For each recipient (excluding sender)
      for (String userId in userIds) {
        if (userId != senderId) {
          // Check if recipient is currently active in this chat
          final presenceService = PresenceService();
          bool isActive =
              await presenceService.isUserActiveInChat(userId, chatId);

          // Only send notification if user is not actively viewing the chat
          if (!isActive) {
            // Use enhanced notification service for WhatsApp-like features
            final enhancedNotificationService = EnhancedNotificationService();
            await enhancedNotificationService.sendPushNotification(
              body: mediaDescription,
              recipientId: userId,
              chatId: chatId,
              title: isGroupChat ? chatData['name'] ?? 'Group Chat' : senderName,
              data: {
                'senderId': senderId,
                'senderName': senderName,
                'messageType': mediaType,
                'isGroupChat': isGroupChat.toString(),
                'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
              },
            );

            print('Enhanced media notification sent to $userId for $mediaType in chat $chatId');
          } else {
            print(
                'User $userId is active in chat $chatId, no media notification sent');
          }
        }
      }
    } catch (e) {
      // Log but don't fail the message send process
      print('Error sending media notification: $e');
    }
  }

  // Send an image message immediately with upload status - WhatsApp style
  Future<String> sendImageMessageInstant(
      String chatId, String localPath, String senderId, String fileName) async {
    if (_isWindowsWithoutFirebase) {
      print('Image message sending skipped on Windows');
      return '';
    }

    try {
      // Add image message to chat collection immediately with upload status
      DocumentReference docRef = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'content': localPath, // Initially use local path
        'senderId': senderId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'image',
        'readBy': [senderId],
        'uploadStatus': 'uploading', // Track upload status
        'fileName': fileName,
        'localPath': localPath,
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

      // Send enhanced notifications for image
      _sendMediaNotificationToRecipients(chatId, senderId, '📷 Photo', 'image');

      // Start background upload
      _uploadImageInBackground(chatId, docRef.id, localPath, fileName);
      
      return docRef.id;
    } catch (e) {
      print('Error sending image message: $e');
      throw e;
    }
  }

  // Background image upload
  Future<void> _uploadImageInBackground(String chatId, String messageId, String localPath, String fileName) async {
    try {
      // Upload to Firebase Storage
      final ref = _storage.ref().child('images/${DateTime.now().millisecondsSinceEpoch}_$fileName');
      UploadTask uploadTask = ref.putFile(File(localPath));
      
      // Update upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        _updateMessageUploadProgress(chatId, messageId, progress);
      });

      // Wait for upload completion
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      // Update message with final URL and completed status
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'content': downloadUrl,
        'uploadStatus': 'completed',
        'uploadProgress': 100.0,
      });

    } catch (e) {
      print('Error uploading image: $e');
      // Update message with error status
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'uploadStatus': 'failed',
        'error': e.toString(),
      });
    }
  }

  // Update message upload progress
  Future<void> _updateMessageUploadProgress(String chatId, String messageId, double progress) async {
    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'uploadProgress': progress * 100,
      });
    } catch (e) {
      print('Error updating upload progress: $e');
    }
  }

  // Legacy method for backward compatibility
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
        'readBy': [senderId], // Initialize with sender as having read it
        'uploadStatus': 'completed', // Mark as already uploaded
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

      // Send enhanced notifications for image
      _sendMediaNotificationToRecipients(chatId, senderId, '📷 Photo', 'image');
    } catch (e) {
      print('Error sending image message: $e');
      throw e;
    }
  }

  // Send a document message
  Future<void> sendDocumentMessage(
      String chatId, String documentUrl, String senderId, String fileName, int fileSize) async {
    if (_isWindowsWithoutFirebase) {
      print('Document message sending skipped on Windows');
      return;
    }

    try {
      // Add document message to chat collection
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'content': documentUrl,
        'senderId': senderId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'document',
        'fileName': fileName,
        'fileSize': fileSize,
        'readBy': [senderId], // Initialize with sender as having read it
      });

      // Update chat metadata with indicator of document message
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': PlatformHelper.isDesktop ? '📄 Document' : '📄 $fileName',
        'lastMessageSenderId': senderId,
        'lastMessageReadBy': [senderId],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Clear typing indicator when sending a message
      await setTypingStatus(chatId, senderId, false);

      // Send enhanced notifications for document
      _sendMediaNotificationToRecipients(chatId, senderId, '📄 Document', 'document');
    } catch (e) {
      print('Error sending document message: $e');
      throw e;
    }
  }

  // Send a document message instantly (WhatsApp-like)
  Future<String> sendDocumentMessageInstant(
      String chatId, String localPath, String senderId, String fileName, int fileSize) async {
    if (_isWindowsWithoutFirebase) {
      print('Document message sending skipped on Windows');
      return '';
    }

    try {
      // Add document message to chat collection immediately with upload status
      DocumentReference docRef = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'content': '', // Will be updated with download URL after upload
        'senderId': senderId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'document',
        'fileName': fileName,
        'fileSize': fileSize,
        'readBy': [senderId],
        'uploadStatus': 'uploading', // Track upload status
        'uploadProgress': 0.0, // Track upload progress
      });

      String messageId = docRef.id;

      // Update chat metadata
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': PlatformHelper.isDesktop ? '📄 Document' : '📄 $fileName',
        'lastMessageSenderId': senderId,
        'lastMessageReadBy': [senderId],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Clear typing indicator
      await setTypingStatus(chatId, senderId, false);

      // Start background upload
      _uploadDocumentInBackground(chatId, messageId, localPath, fileName);

      return messageId;
    } catch (e) {
      print('Error sending document message instantly: $e');
      throw e;
    }
  }

  // Upload document in background
  Future<void> _uploadDocumentInBackground(
      String chatId, String messageId, String localPath, String fileName) async {
    try {
      // Create unique filename
      final String uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final String filePath = 'chat_documents/$chatId/$uniqueFileName';

      // Upload to Firebase Storage
      final Reference storageRef = _storage.ref().child(filePath);
      
      UploadTask uploadTask;
      if (kIsWeb) {
        final file = File(localPath);
        final bytes = await file.readAsBytes();
        uploadTask = storageRef.putData(bytes);
      } else {
        uploadTask = storageRef.putFile(File(localPath));
      }

      // Update upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        _updateMessageUploadProgress(chatId, messageId, progress);
      });

      // Wait for upload completion
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      // Update message with final URL and completed status
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'content': downloadUrl,
        'uploadStatus': 'completed',
        'uploadProgress': 100.0,
      });

      // Send notification after upload completes
      _sendMediaNotificationToRecipients(chatId, '', '📄 Document', 'document');

    } catch (e) {
      print('Error uploading document: $e');
      // Update message with error status
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'uploadStatus': 'failed',
        'uploadProgress': 0.0,
      });
    }
  }

  // Send a location message
  Future<void> sendLocationMessage(
      String chatId, String senderId, double latitude, double longitude) async {
    if (_isWindowsWithoutFirebase) {
      print('Location message sending skipped on Windows');
      return;
    }

    try {
      // Add location message to chat collection
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'content': 'Location: $latitude, $longitude',
        'senderId': senderId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'location',
        'latitude': latitude,
        'longitude': longitude,
        'readBy': [senderId], // Initialize with sender as having read it
      });

      // Update chat metadata with indicator of location message
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': PlatformHelper.isDesktop ? '📍 Location' : '📍 Location shared',
        'lastMessageSenderId': senderId,
        'lastMessageReadBy': [senderId],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Clear typing indicator when sending a message
      await setTypingStatus(chatId, senderId, false);

      // Send enhanced notifications for location
      _sendMediaNotificationToRecipients(chatId, senderId, '📍 Location', 'location');
    } catch (e) {
      print('Error sending location message: $e');
      throw e;
    }
  }

  // Send a location message instantly (already instant, but keeping for consistency)
  Future<String> sendLocationMessageInstant(
      String chatId, String senderId, double latitude, double longitude) async {
    if (_isWindowsWithoutFirebase) {
      print('Location message sending skipped on Windows');
      return '';
    }

    try {
      // Add location message to chat collection
      DocumentReference docRef = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'content': 'Location: $latitude, $longitude',
        'senderId': senderId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'location',
        'latitude': latitude,
        'longitude': longitude,
        'readBy': [senderId],
      });

      // Update chat metadata with indicator of location message
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': PlatformHelper.isDesktop ? '📍 Location' : '📍 Location shared',
        'lastMessageSenderId': senderId,
        'lastMessageReadBy': [senderId],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Clear typing indicator when sending a message
      await setTypingStatus(chatId, senderId, false);

      // Send enhanced notifications for location
      _sendMediaNotificationToRecipients(chatId, senderId, '📍 Location', 'location');

      return docRef.id;
    } catch (e) {
      print('Error sending location message: $e');
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
      // First mark the chat as read at the chat level
      await markChatAsRead(chatId, userId);

      // Use a simpler approach - get all recent messages and filter in code
      final messagesQuery = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(50) // Get most recent 50 messages
          .get();

      // Use a batch to update multiple messages efficiently
      final batch = _firestore.batch();
      final now = FieldValue.serverTimestamp();
      int updatedCount = 0;

      for (var doc in messagesQuery.docs) {
        Map<String, dynamic> data = doc.data();
        String senderId = data['senderId'] ?? '';
        
        // Only process messages NOT sent by the current user
        if (senderId == userId) continue;
        
        // Initialize empty list if readBy doesn't exist
        List<dynamic> readBy = [];
        
        if (data.containsKey('readBy') && data['readBy'] != null) {
          readBy = List<dynamic>.from(data['readBy']);
        }

        // Only update if user hasn't read it yet
        if (!readBy.contains(userId)) {
          readBy.add(userId);
          batch.update(doc.reference, {
            'readBy': readBy,
            'readTimestamp': now,
          });

          updatedCount++;
        }
      }

      if (updatedCount > 0) {
        await batch.commit();
      }
    } catch (e) {
      print('❌ Error marking messages as read: $e');
    }
  }

  // Get messages stream for a chat
  Stream<List<Message>> getMessages(String chatId, String currentUserId) {
    if (_isWindowsWithoutFirebase) {
      // Return empty messages list for Windows
      return Stream.value([]);
    }

    // Create a stream that will give us new messages
    final messagesStream = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();

    // Combine both streams to ensure we get updates when either messages or read statuses change
    return messagesStream.map((snapshot) {
      // NOTE: markMessagesAsRead removed from here — it caused a feedback loop:
      // timer writes readBy → snapshot fires → mapper calls markMessagesAsRead → more writes.
      // Read-marking is now handled by a debouncer in chat_screen.dart.

      return snapshot.docs.map((doc) {
        try {
          final data = doc.data();

          // Add document ID to the data for better message identification
          final Map<String, dynamic> messageData = {
            ...data,
            'id': doc.id, // Ensure ID is always available
          };

          // Create message from JSON data
          final message = Message.fromJson(messageData, currentUserId);

          return message;
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

  // Add or remove a reaction to a message
  Future<void> toggleMessageReaction(
    String chatId,
    String messageId,
    String emoji,
    String userId,
    String userDisplayName,
  ) async {
    if (_isWindowsWithoutFirebase) return;

    try {
      final messageRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);

      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot messageSnapshot = await transaction.get(messageRef);

        if (!messageSnapshot.exists) {
          throw Exception("Message does not exist!");
        }

        final messageData = messageSnapshot.data() as Map<String, dynamic>;
        List<Map<String, dynamic>> reactions =
            List<Map<String, dynamic>>.from(messageData['reactions'] ?? []);

        // Check if the user has already reacted with this emoji
        final existingReactionIndex = reactions.indexWhere((reaction) =>
            reaction['userId'] == userId && reaction['emoji'] == emoji);

        if (existingReactionIndex != -1) {
          // User already reacted with this emoji, remove it
          reactions.removeAt(existingReactionIndex);
          print('Removed reaction $emoji from message $messageId by user $userId');
        } else {
          // Add new reaction
          reactions.add({
            'userId': userId,
            'emoji': emoji,
            'timestamp': FieldValue.serverTimestamp(),
            'userDisplayName': userDisplayName,
          });
          print('Added reaction $emoji to message $messageId by user $userId');
        }

        transaction.update(messageRef, {'reactions': reactions});
      });
    } catch (e) {
      print('Error toggling message reaction: $e');
      throw e;
    }
  }

  // Get reaction summary for a message
  Future<List<MessageReactionSummary>> getMessageReactionSummary(
    String chatId,
    String messageId,
    String currentUserId,
  ) async {
    if (_isWindowsWithoutFirebase) return [];

    try {
      final messageDoc = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .get();

      if (!messageDoc.exists) return [];

      final messageData = messageDoc.data() as Map<String, dynamic>;
      final reactions = (messageData['reactions'] as List<dynamic>?)
              ?.map((r) => MessageReaction.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [];

      // Group reactions by emoji
      final emojiGroups = <String, List<MessageReaction>>{};
      for (final reaction in reactions) {
        emojiGroups.putIfAbsent(reaction.emoji, () => []).add(reaction);
      }

      return emojiGroups.keys
          .map((emoji) => MessageReactionSummary.fromReactions(
                reactions,
                emoji,
                currentUserId,
              ))
          .toList();
    } catch (e) {
      print('Error getting reaction summary: $e');
      return [];
    }
  }

  // Delete a message for the current user only (hides it from their view)
  Future<void> deleteMessageForMe(
    String chatId,
    String messageId,
    String userId,
  ) async {
    if (_isWindowsWithoutFirebase) return;

    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'deletedFor': FieldValue.arrayUnion([userId]),
      });
      print('Message $messageId deleted for user $userId');
    } catch (e) {
      print('Error deleting message for me: $e');
      rethrow;
    }
  }

  // Delete a message for everyone (replaces content with deleted placeholder)
  Future<void> deleteMessageForEveryone(
    String chatId,
    String messageId,
    String userId,
  ) async {
    if (_isWindowsWithoutFirebase) return;

    try {
      final messageRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);

      // Verify the sender is the one deleting
      final messageDoc = await messageRef.get();
      if (!messageDoc.exists) throw Exception('Message not found');

      final data = messageDoc.data() as Map<String, dynamic>;
      if (data['senderId'] != userId) {
        throw Exception('Only the sender can delete a message for everyone');
      }

      // Update the message
      await messageRef.update({
        'isDeleted': true,
        'deletedBy': userId,
        'content': '',
        'reactions': [],
      });

      // If this was the last message in the chat, update the chat preview
      final chatRef = _firestore.collection('chats').doc(chatId);
      final chatDoc = await chatRef.get();
      if (chatDoc.exists) {
        final chatData = chatDoc.data() as Map<String, dynamic>;
        final lastMessageId = chatData['lastMessageId'];
        if (lastMessageId == messageId) {
          await chatRef.update({
            'lastMessage': 'This message was deleted',
          });
        }
      }

      print('Message $messageId deleted for everyone by $userId');
    } catch (e) {
      print('Error deleting message for everyone: $e');
      rethrow;
    }
  }

  // ─── Block User Methods ──────────────────────────────

  /// Block a user. Adds [blockedUserId] to the current user's blockedUsers array.
  Future<void> blockUser(String currentUserId, String blockedUserId) async {
    if (_isWindowsWithoutFirebase) return;
    try {
      await _firestore.collection('users').doc(currentUserId).update({
        'blockedUsers': FieldValue.arrayUnion([blockedUserId]),
      });
    } catch (e) {
      print('Error blocking user: $e');
      rethrow;
    }
  }

  /// Unblock a user. Removes [blockedUserId] from the current user's blockedUsers array.
  Future<void> unblockUser(String currentUserId, String blockedUserId) async {
    if (_isWindowsWithoutFirebase) return;
    try {
      await _firestore.collection('users').doc(currentUserId).update({
        'blockedUsers': FieldValue.arrayRemove([blockedUserId]),
      });
    } catch (e) {
      print('Error unblocking user: $e');
      rethrow;
    }
  }

  /// Returns a real-time stream of block status between two users.
  /// Emits a record with two booleans: (blockedByMe, blockedByOther).
  Stream<({bool blockedByMe, bool blockedByOther})> blockStatusStream(
      String currentUserId, String otherUserId) {
    final myDoc = _firestore.collection('users').doc(currentUserId).snapshots();

    return myDoc.asyncMap((mySnap) async {
      final myData = mySnap.data() ?? {};
      final myBlockedList = List<String>.from(myData['blockedUsers'] ?? []);
      final blockedByMe = myBlockedList.contains(otherUserId);

      // Also check if the other user blocked me
      final otherSnap =
          await _firestore.collection('users').doc(otherUserId).get();
      final otherData = otherSnap.data() ?? {};
      final otherBlockedList =
          List<String>.from(otherData['blockedUsers'] ?? []);
      final blockedByOther = otherBlockedList.contains(currentUserId);

      return (blockedByMe: blockedByMe, blockedByOther: blockedByOther);
    });
  }
}
