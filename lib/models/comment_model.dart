import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single comment on a post.
///
/// Stored at `posts/{postId}/comments/{commentId}` in Firestore.
class Comment {
  final String id;
  final String postId;
  final String userId;
  final String username;
  final String userProfileImage;
  final String text;
  final DateTime timestamp;
  final List<String> likes;
  final String? replyTo; // commentId this is replying to (future use)

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.username,
    required this.userProfileImage,
    required this.text,
    required this.timestamp,
    required this.likes,
    this.replyTo,
  });

  bool isLikedBy(String userId) => likes.contains(userId);

  int get likeCount => likes.length;

  factory Comment.fromFirestore(DocumentSnapshot doc, {required String postId}) {
    final data = doc.data() as Map<String, dynamic>;
    return Comment(
      id: doc.id,
      postId: postId,
      userId: data['userId'] ?? '',
      username: data['username'] ?? 'Anonymous',
      userProfileImage: data['userProfileImage'] ?? '',
      text: data['text'] ?? '',
      timestamp: data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      likes: List<String>.from(data['likes'] ?? []),
      replyTo: data['replyTo'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
      'userProfileImage': userProfileImage,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': likes,
      if (replyTo != null) 'replyTo': replyTo,
    };
  }

  Comment copyWith({
    String? id,
    String? postId,
    String? userId,
    String? username,
    String? userProfileImage,
    String? text,
    DateTime? timestamp,
    List<String>? likes,
    String? replyTo,
  }) {
    return Comment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userProfileImage: userProfileImage ?? this.userProfileImage,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      likes: likes ?? this.likes,
      replyTo: replyTo ?? this.replyTo,
    );
  }
}
