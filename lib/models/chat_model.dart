import 'package:cloud_firestore/cloud_firestore.dart';

class Chat {
  final String id;
  final String name;
  final String lastMessage;
  final List<String> userIds;

  Chat({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.userIds,
  });

  factory Chat.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Chat(
      id: doc.id,
      name: data['name'] ?? '',
      lastMessage: data['lastMessage'] ?? '',
      userIds: List<String>.from(data['userIds']),
    );
  }
}