import 'package:cloud_firestore/cloud_firestore.dart';

enum PostPrivacy {
  public,    // Visible to everyone
  friends,   // Visible only to friends
  private    // Visible only to the creator
}

class Post {
  final String id;
  final String userId;
  final String username;
  final String userProfileImage;
  final String caption;
  final String imageUrl;
  final List<String> imageUrls;
  final DateTime timestamp;
  final List<String> likes;
  final int commentsCount;
  final String location;
  final PostPrivacy privacy;

  Post({
    required this.id,
    required this.userId,
    required this.username,
    required this.userProfileImage,
    required this.caption,
    required this.imageUrl,
    this.imageUrls = const [],
    required this.timestamp,
    required this.likes,
    required this.commentsCount,
    this.location = '',
    this.privacy = PostPrivacy.public,
  });

  /// Returns the full list of image URLs, handling backward compatibility.
  /// If imageUrls is populated, use it. Otherwise fall back to single imageUrl.
  List<String> get allImageUrls {
    if (imageUrls.isNotEmpty) return imageUrls;
    if (imageUrl.isNotEmpty) return [imageUrl];
    return [];
  }

  /// Whether this post has multiple images (carousel).
  bool get isCarousel => allImageUrls.length > 1;

  bool isLikedBy(String userId) {
    return likes.contains(userId);
  }

  factory Post.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Convert string privacy setting to enum
    PostPrivacy privacySetting = PostPrivacy.public;
    if (data['privacy'] != null) {
      switch (data['privacy']) {
        case 'public':
          privacySetting = PostPrivacy.public;
          break;
        case 'friends':
          privacySetting = PostPrivacy.friends;
          break;
        case 'private':
          privacySetting = PostPrivacy.private;
          break;
      }
    }

    // Read imageUrls list if present, otherwise empty
    List<String> imageUrlsList = [];
    if (data['imageUrls'] != null) {
      imageUrlsList = List<String>.from(data['imageUrls']);
    }

    return Post(
      id: doc.id,
      userId: data['userId'] ?? '',
      username: data['username'] ?? 'Anonymous',
      userProfileImage: data['userProfileImage'] ?? '',
      caption: data['caption'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      imageUrls: imageUrlsList,
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      likes: List<String>.from(data['likes'] ?? []),
      commentsCount: data['commentsCount'] ?? 0,
      location: data['location'] ?? '',
      privacy: privacySetting,
    );
  }

  Map<String, dynamic> toMap() {
    // Convert enum to string for storage
    String privacyString;
    switch (privacy) {
      case PostPrivacy.public:
        privacyString = 'public';
        break;
      case PostPrivacy.friends:
        privacyString = 'friends';
        break;
      case PostPrivacy.private:
        privacyString = 'private';
        break;
    }

    // For backward compat: imageUrl stores the first image,
    // imageUrls stores the full list
    final urls = allImageUrls;

    return {
      'userId': userId,
      'username': username,
      'userProfileImage': userProfileImage,
      'caption': caption,
      'imageUrl': urls.isNotEmpty ? urls.first : imageUrl,
      'imageUrls': urls,
      'timestamp': Timestamp.fromDate(timestamp),
      'likes': likes,
      'commentsCount': commentsCount,
      'location': location,
      'privacy': privacyString,
    };
  }

  Post copyWith({
    String? id,
    String? userId,
    String? username,
    String? userProfileImage,
    String? caption,
    String? imageUrl,
    List<String>? imageUrls,
    DateTime? timestamp,
    List<String>? likes,
    int? commentsCount,
    String? location,
    PostPrivacy? privacy,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userProfileImage: userProfileImage ?? this.userProfileImage,
      caption: caption ?? this.caption,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      timestamp: timestamp ?? this.timestamp,
      likes: likes ?? this.likes,
      commentsCount: commentsCount ?? this.commentsCount,
      location: location ?? this.location,
      privacy: privacy ?? this.privacy,
    );
  }
}
