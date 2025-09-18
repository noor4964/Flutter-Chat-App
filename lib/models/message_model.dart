import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/models/message_reaction.dart';

class Message {
  final String id;
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isMe;
  final bool isRead;
  final List<String>? readBy; // Added readBy field
  final String type;
  final DateTime?
      readTimestamp; // Added readTimestamp to track when message was read
  final List<MessageReaction> reactions; // Added reactions field

  Message({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.isMe,
    required this.isRead,
    this.readBy, // Added readBy parameter
    this.type = 'text',
    this.readTimestamp, // Added readTimestamp parameter
    this.reactions = const [], // Added reactions parameter
  });

  factory Message.fromJson(Map<String, dynamic> json, String currentUserId) {
    // Check if this is a message sent by the current user
    String senderId = json['senderId'] ?? '';
    bool isSentByCurrentUser = senderId == currentUserId;

    // For debugging
    print(
        'Processing message: ${json['id'] ?? json['documentId'] ?? 'unknown'}, ' +
            'sender: $senderId, currentUser: $currentUserId, ' +
            'readBy: ${json['readBy']}');

    // For sender's messages, isRead means someone else read it
    // For receiver's messages, isRead means current user read it
    bool isReadStatus = false;
    DateTime? readTime;

    if (isSentByCurrentUser) {
      // If I'm the sender, message is read if anyone else read it
      List<dynamic> readByList = List<dynamic>.from(json['readBy'] ?? []);

      // Filter out the current user and empty strings, keep only other valid user IDs
      List<String> validReadByIds = readByList
          .where((id) => id is String && id.isNotEmpty && id != currentUserId)
          .cast<String>()
          .toList();

      isReadStatus = validReadByIds.isNotEmpty;

      // Enhanced debug logging for read status
      print('📝 Message ${json['id']} sent by me:');
      print('   📋 Raw readBy: $readByList');
      print('   ✅ Valid readBy IDs (others): $validReadByIds');
      print('   👁️ IsRead: $isReadStatus');
      print('   👤 Current user: $currentUserId');

      // If read, use the readTimestamp when available
      if (isReadStatus && json['readTimestamp'] != null) {
        if (json['readTimestamp'] is Timestamp) {
          readTime = (json['readTimestamp'] as Timestamp).toDate();
          print('   ⏰ Read timestamp: $readTime');
        } else if (json['readTimestamp'] is DateTime) {
          readTime = json['readTimestamp'] as DateTime;
          print('   ⏰ Read timestamp: $readTime');
        }
      }
    } else {
      // If I'm the receiver, message is read if I read it (readBy contains my ID)
      List<dynamic> readByList = List<dynamic>.from(json['readBy'] ?? []);
      isReadStatus = readByList.contains(currentUserId);
      print('📨 Message ${json['id']} received by me:');
      print('   📋 ReadBy: $readByList');
      print('   👁️ IsRead: $isReadStatus');
      print('   👤 Current user: $currentUserId');
    }

    return Message(
      id: json['id'] ?? json['documentId'] ?? '',
      sender: senderId,
      text: json['content'] ?? '',
      timestamp: json['timestamp'] != null
          ? (json['timestamp'] is Timestamp
              ? (json['timestamp'] as Timestamp).toDate()
              : (json['timestamp'] is DateTime
                  ? json['timestamp'] as DateTime
                  : DateTime.now()))
          : DateTime.now(),
      isMe: isSentByCurrentUser,
      isRead: isReadStatus,
      readBy: List<String>.from(
          (json['readBy'] ?? []).whereType<String>()), // Parse readBy field
      type: json['type'] ?? 'text',
      readTimestamp: readTime,
      reactions: (json['reactions'] as List<dynamic>?)
              ?.map((r) => MessageReaction.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [], // Parse reactions field
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': sender,
      'content': text,
      'timestamp': timestamp,
      'readBy': readBy ?? [],
      'type': type,
      'readTimestamp': readTimestamp,
      'reactions': reactions.map((r) => r.toJson()).toList(),
    };
  }

  // Helper methods for reactions
  List<MessageReactionSummary> getReactionSummaries(String currentUserId) {
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
  }

  bool hasReactionFromUser(String userId, String emoji) {
    return reactions.any((r) => r.userId == userId && r.emoji == emoji);
  }
}
