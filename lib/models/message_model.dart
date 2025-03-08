import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String sender;
  final String text;
  final DateTime timestamp;
  final String currentUserId;
  final List<String> readBy;

  bool get isMe => sender == currentUserId;
  bool get isRead => readBy.contains(currentUserId);

  Message({
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.currentUserId,
    required this.readBy,
  });

  factory Message.fromJson(Map<String, dynamic> json, String currentUserId) {
    return Message(
      sender: json['sender'],
      text: json['text'],
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      currentUserId: currentUserId,
      readBy: List<String>.from(json['readBy'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'readBy': readBy,
    };
  }
}