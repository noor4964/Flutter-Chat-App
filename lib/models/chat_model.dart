import 'package:cloud_firestore/cloud_firestore.dart';

class Chat {
  final String id;
  final String name;
  final String lastMessage;
  final List<String> userIds;
  final DateTime createdAt;

  Chat({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.userIds,
    required this.createdAt,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'],
      name: json['name'],
      lastMessage: json['lastMessage'],
      userIds: List<String>.from(json['userIds']),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lastMessage': lastMessage,
      'userIds': userIds,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}