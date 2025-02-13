import 'package:cloud_firestore/cloud_firestore.dart';

class Chat {
  final String id;
  final String name;
  final String lastMessage;
  final List<String> participants;

  Chat({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.participants,
  });

  factory Chat.fromFirestore(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    return Chat(
      id: doc.id,
      name: data['chatName'] ?? 'Unknown Chat',
      lastMessage: data['lastMessage'] ?? '',
      participants: List<String>.from(data['participants'] ?? []),
    );
  }
}