import 'package:cloud_firestore/cloud_firestore.dart';

class Story {
  final String id;
  final String userId;
  final String username;
  final String userProfileImage;
  final String mediaUrl;
  final DateTime timestamp;
  final DateTime expiryTime; // Stories expire after 24 hours
  final String caption;
  final List<String> viewers; // Users who have viewed this story
  final String background; // For text-only stories, can be a color or gradient
  final String mediaType; // 'image', 'video', or 'text'
  final bool isHighlighted; // If story is saved to highlights

  Story({
    required this.id,
    required this.userId,
    required this.username,
    required this.userProfileImage,
    required this.mediaUrl,
    required this.timestamp,
    required this.expiryTime,
    this.caption = '',
    required this.viewers,
    this.background = '',
    this.mediaType = 'image',
    this.isHighlighted = false,
  });

  bool isViewed(String viewerId) {
    return viewers.contains(viewerId);
  }

  bool get isExpired {
    return DateTime.now().isAfter(expiryTime);
  }

  // Calculate how much time is left before story expires (0-100)
  double get timeLeftPercent {
    if (isExpired) return 0;

    final totalDuration = expiryTime.difference(timestamp).inMilliseconds;
    final timeLeft = expiryTime.difference(DateTime.now()).inMilliseconds;

    return (timeLeft / totalDuration).clamp(0.0, 1.0) * 100;
  }

  factory Story.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Story(
      id: doc.id,
      userId: data['userId'] ?? '',
      username: data['username'] ?? 'Anonymous',
      userProfileImage: data['userProfileImage'] ?? '',
      mediaUrl: data['mediaUrl'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      expiryTime: (data['expiryTime'] as Timestamp).toDate(),
      caption: data['caption'] ?? '',
      viewers: List<String>.from(data['viewers'] ?? []),
      background: data['background'] ?? '',
      mediaType: data['mediaType'] ?? 'image',
      isHighlighted: data['isHighlighted'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
      'userProfileImage': userProfileImage,
      'mediaUrl': mediaUrl,
      'timestamp': Timestamp.fromDate(timestamp),
      'expiryTime': Timestamp.fromDate(expiryTime),
      'caption': caption,
      'viewers': viewers,
      'background': background,
      'mediaType': mediaType,
      'isHighlighted': isHighlighted,
    };
  }

  Story copyWith({
    String? id,
    String? userId,
    String? username,
    String? userProfileImage,
    String? mediaUrl,
    DateTime? timestamp,
    DateTime? expiryTime,
    String? caption,
    List<String>? viewers,
    String? background,
    String? mediaType,
    bool? isHighlighted,
  }) {
    return Story(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userProfileImage: userProfileImage ?? this.userProfileImage,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      timestamp: timestamp ?? this.timestamp,
      expiryTime: expiryTime ?? this.expiryTime,
      caption: caption ?? this.caption,
      viewers: viewers ?? this.viewers,
      background: background ?? this.background,
      mediaType: mediaType ?? this.mediaType,
      isHighlighted: isHighlighted ?? this.isHighlighted,
    );
  }
}
