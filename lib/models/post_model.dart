import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String userId;
  final String username;
  final String userProfileImage;
  final String caption;
  final String imageUrl;
  final DateTime timestamp;
  final List<String> likes;
  final int commentsCount;
  final String location;

  Post({
    required this.id,
    required this.userId,
    required this.username,
    required this.userProfileImage,
    required this.caption,
    required this.imageUrl,
    required this.timestamp,
    required this.likes,
    required this.commentsCount,
    this.location = '',
  });

  bool isLikedBy(String userId) {
    return likes.contains(userId);
  }

  factory Post.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Post(
      id: doc.id,
      userId: data['userId'] ?? '',
      username: data['username'] ?? 'Anonymous',
      userProfileImage: data['userProfileImage'] ?? '',
      caption: data['caption'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      likes: List<String>.from(data['likes'] ?? []),
      commentsCount: data['commentsCount'] ?? 0,
      location: data['location'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
      'userProfileImage': userProfileImage,
      'caption': caption,
      'imageUrl': imageUrl,
      'timestamp': Timestamp.fromDate(timestamp),
      'likes': likes,
      'commentsCount': commentsCount,
      'location': location,
    };
  }

  Post copyWith({
    String? id,
    String? userId,
    String? username,
    String? userProfileImage,
    String? caption,
    String? imageUrl,
    DateTime? timestamp,
    List<String>? likes,
    int? commentsCount,
    String? location,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userProfileImage: userProfileImage ?? this.userProfileImage,
      caption: caption ?? this.caption,
      imageUrl: imageUrl ?? this.imageUrl,
      timestamp: timestamp ?? this.timestamp,
      likes: likes ?? this.likes,
      commentsCount: commentsCount ?? this.commentsCount,
      location: location ?? this.location,
    );
  }
}
