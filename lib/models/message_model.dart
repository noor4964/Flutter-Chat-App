import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String sender;
  final String text;
  final DateTime timestamp;
  final String currentUserId;

  bool get isMe => sender == currentUserId;

  Message({
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.currentUserId,
  });

  factory Message.fromJson(Map<String, dynamic> json, String currentUserId) {
    return Message(
      sender: json['sender'],
      text: json['text'],
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      currentUserId: currentUserId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}