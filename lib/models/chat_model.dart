import 'package:cloud_firestore/cloud_firestore.dart';

class Chat {
  final String id;
  final String name;
  final String lastMessage;
  final List<String> participants;

  // Group chat fields
  final bool isGroup;
  final String? groupName;
  final String? groupImageUrl;
  final String? groupDescription;
  final String? createdBy;
  final List<String> admins;
  final Map<String, String> memberRoles; // uid -> 'admin' | 'member'
  final Timestamp? createdAt;

  Chat({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.participants,
    this.isGroup = false,
    this.groupName,
    this.groupImageUrl,
    this.groupDescription,
    this.createdBy,
    this.admins = const [],
    this.memberRoles = const {},
    this.createdAt,
  });

  factory Chat.fromFirestore(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    return Chat(
      id: doc.id,
      name: data['chatName'] ?? data['groupName'] ?? 'Unknown Chat',
      lastMessage: data['lastMessage'] ?? '',
      participants: List<String>.from(data['participants'] ?? data['userIds'] ?? []),
      isGroup: data['isGroup'] ?? false,
      groupName: data['groupName'],
      groupImageUrl: data['groupImageUrl'],
      groupDescription: data['groupDescription'],
      createdBy: data['createdBy'],
      admins: List<String>.from(data['admins'] ?? []),
      memberRoles: Map<String, String>.from(data['memberRoles'] ?? {}),
      createdAt: data['createdAt'],
    );
  }

  /// Display name: group name for groups, or partner name for 1:1
  String get displayName => isGroup ? (groupName ?? 'Group Chat') : name;
}