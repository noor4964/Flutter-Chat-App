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

  Message({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.isMe,
    required this.isRead,
    this.readBy, // Added readBy parameter
    this.type = 'text',
  });

  factory Message.fromJson(Map<String, dynamic> json, String currentUserId) {
    return Message(
      id: json['id'] ?? '',
      sender: json['senderId'] ?? '',
      text: json['content'] ?? '',
      timestamp: json['timestamp'] != null
          ? (json['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      isMe: json['senderId'] == currentUserId,
      isRead: (json['readBy'] ?? []).contains(currentUserId),
      readBy: List<String>.from(json['readBy'] ?? []), // Parse readBy field
      type: json['type'] ?? 'text',
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
    };
  }
}
