import 'package:cloud_firestore/cloud_firestore.dart';

class MessageReaction {
  final String userId;
  final String emoji;
  final DateTime timestamp;
  final String? userDisplayName;

  MessageReaction({
    required this.userId,
    required this.emoji,
    required this.timestamp,
    this.userDisplayName,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      userId: json['userId'] ?? '',
      emoji: json['emoji'] ?? '',
      timestamp: json['timestamp'] is Timestamp
          ? (json['timestamp'] as Timestamp).toDate()
          : json['timestamp'] is DateTime
              ? json['timestamp']
              : DateTime.now(),
      userDisplayName: json['userDisplayName'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'emoji': emoji,
      'timestamp': Timestamp.fromDate(timestamp),
      'userDisplayName': userDisplayName,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageReaction &&
        other.userId == userId &&
        other.emoji == emoji;
  }

  @override
  int get hashCode => Object.hash(userId, emoji);
}

class MessageReactionSummary {
  final String emoji;
  final int count;
  final List<String> userIds;
  final bool hasCurrentUserReacted;

  MessageReactionSummary({
    required this.emoji,
    required this.count,
    required this.userIds,
    required this.hasCurrentUserReacted,
  });

  factory MessageReactionSummary.fromReactions(
    List<MessageReaction> reactions,
    String emoji,
    String currentUserId,
  ) {
    final emojiReactions = reactions.where((r) => r.emoji == emoji).toList();
    return MessageReactionSummary(
      emoji: emoji,
      count: emojiReactions.length,
      userIds: emojiReactions.map((r) => r.userId).toList(),
      hasCurrentUserReacted: emojiReactions.any((r) => r.userId == currentUserId),
    );
  }
}