import 'package:cloud_firestore/cloud_firestore.dart';

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

      // More explicit check: readBy contains any userId that isn't mine
      isReadStatus = readByList
          .where((id) => id != currentUserId && id is String)
          .isNotEmpty;

      // Debug logging for read status
      print('Message sent by me, readBy: $readByList, isRead: $isReadStatus');

      // If read, use the readTimestamp when available
      if (isReadStatus && json['readTimestamp'] != null) {
        if (json['readTimestamp'] is Timestamp) {
          readTime = (json['readTimestamp'] as Timestamp).toDate();
          print('Read timestamp found: $readTime');
        } else if (json['readTimestamp'] is DateTime) {
          readTime = json['readTimestamp'] as DateTime;
          print('Read timestamp found: $readTime');
        }
      }
    } else {
      // If I'm the receiver, message is read if I read it (readBy contains my ID)
      List<dynamic> readByList = List<dynamic>.from(json['readBy'] ?? []);
      isReadStatus = readByList.contains(currentUserId);
      print(
          'Message received by me, readBy: $readByList, isRead: $isReadStatus');
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
    };
  }
}
