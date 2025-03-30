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
  final Map<String, dynamic>? musicInfo; // Music associated with the story
  final List<String> mentions; // Users mentioned in the story
  final String? location; // Location associated with the story
  final String? filter; // Applied filter name
  final List<Map<String, dynamic>> reactions; // Reactions from viewers
  final bool allowSharing; // Whether story can be shared or not
  final List<Map<String, dynamic>> replies; // Replies to the story

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
    this.musicInfo,
    this.mentions = const [],
    this.location,
    this.filter,
    this.reactions = const [],
    this.allowSharing = true,
    this.replies = const [],
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

  // Calculate the time remaining in human-readable format
  String get timeLeftFormatted {
    if (isExpired) return 'Expired';

    final Duration timeLeft = expiryTime.difference(DateTime.now());

    if (timeLeft.inHours >= 1) {
      return '${timeLeft.inHours}h ${timeLeft.inMinutes.remainder(60)}m remaining';
    } else if (timeLeft.inMinutes >= 1) {
      return '${timeLeft.inMinutes}m ${timeLeft.inSeconds.remainder(60)}s remaining';
    } else {
      return '${timeLeft.inSeconds}s remaining';
    }
  }

  // Get the reaction count for a specific emoji type
  int getReactionCount(String emoji) {
    return reactions.where((reaction) => reaction['emoji'] == emoji).length;
  }

  // Check if a specific user has reacted with a specific emoji
  bool hasUserReacted(String userId, String emoji) {
    return reactions.any((reaction) =>
        reaction['userId'] == userId && reaction['emoji'] == emoji);
  }

  // Get all user replies
  List<Map<String, dynamic>> get userReplies {
    return List.from(replies);
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
      musicInfo: data['musicInfo'],
      mentions: List<String>.from(data['mentions'] ?? []),
      location: data['location'],
      filter: data['filter'],
      reactions: List<Map<String, dynamic>>.from(data['reactions'] ?? []),
      allowSharing: data['allowSharing'] ?? true,
      replies: List<Map<String, dynamic>>.from(data['replies'] ?? []),
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
      'musicInfo': musicInfo,
      'mentions': mentions,
      'location': location,
      'filter': filter,
      'reactions': reactions,
      'allowSharing': allowSharing,
      'replies': replies,
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
    Map<String, dynamic>? musicInfo,
    List<String>? mentions,
    String? location,
    String? filter,
    List<Map<String, dynamic>>? reactions,
    bool? allowSharing,
    List<Map<String, dynamic>>? replies,
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
      musicInfo: musicInfo ?? this.musicInfo,
      mentions: mentions ?? this.mentions,
      location: location ?? this.location,
      filter: filter ?? this.filter,
      reactions: reactions ?? this.reactions,
      allowSharing: allowSharing ?? this.allowSharing,
      replies: replies ?? this.replies,
    );
  }
}
