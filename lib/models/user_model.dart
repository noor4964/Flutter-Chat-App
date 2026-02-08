import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model representing a user document in Firestore `users/{uid}`.
///
/// Handles null-safety for optional fields that may not exist on older
/// documents created before the field was introduced.
class UserModel {
  final String uid;
  final String username;
  final String email;
  final String? gender;
  final String? bio;
  final String? phone;
  final String? location;
  final String? profileImageUrl;
  final String? coverImageUrl;
  final bool isOnline;
  final DateTime? createdAt;
  final DateTime? lastUpdated;
  final DateTime? lastActive;

  const UserModel({
    required this.uid,
    required this.username,
    required this.email,
    this.gender,
    this.bio,
    this.phone,
    this.location,
    this.profileImageUrl,
    this.coverImageUrl,
    this.isOnline = false,
    this.createdAt,
    this.lastUpdated,
    this.lastActive,
  });

  /// Create a [UserModel] from a Firestore document map.
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String? ?? '',
      username: map['username'] as String? ?? '',
      email: map['email'] as String? ?? '',
      gender: map['gender'] as String?,
      bio: map['bio'] as String?,
      phone: map['phone'] as String?,
      location: map['location'] as String?,
      profileImageUrl: map['profileImageUrl'] as String?,
      coverImageUrl: map['coverImageUrl'] as String?,
      isOnline: map['isOnline'] as bool? ?? false,
      createdAt: _parseTimestamp(map['createdAt']),
      lastUpdated: _parseTimestamp(map['lastUpdated']),
      lastActive: _parseTimestamp(map['lastActive']),
    );
  }

  /// Convert to a Firestore-compatible map.
  /// Does NOT include `uid` or `createdAt` (those are set once at registration).
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'email': email,
      if (gender != null) 'gender': gender,
      if (bio != null) 'bio': bio,
      if (phone != null) 'phone': phone,
      if (location != null) 'location': location,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      if (coverImageUrl != null) 'coverImageUrl': coverImageUrl,
      'isOnline': isOnline,
      'lastUpdated': FieldValue.serverTimestamp(),
    };
  }

  /// Build a partial update map containing only changed fields.
  /// Compares [this] against [original] and returns only the deltas.
  Map<String, dynamic> changedFields(UserModel original) {
    final changes = <String, dynamic>{};
    if (username != original.username) changes['username'] = username;
    if (email != original.email) changes['email'] = email;
    if (bio != original.bio) changes['bio'] = bio ?? '';
    if (phone != original.phone) changes['phone'] = phone ?? '';
    if (location != original.location) changes['location'] = location ?? '';
    if (profileImageUrl != original.profileImageUrl) {
      changes['profileImageUrl'] = profileImageUrl ?? '';
    }
    if (coverImageUrl != original.coverImageUrl) {
      changes['coverImageUrl'] = coverImageUrl ?? '';
    }
    if (changes.isNotEmpty) {
      changes['lastUpdated'] = FieldValue.serverTimestamp();
    }
    return changes;
  }

  /// Create a copy with selected fields replaced.
  UserModel copyWith({
    String? uid,
    String? username,
    String? email,
    String? gender,
    String? bio,
    String? phone,
    String? location,
    String? profileImageUrl,
    String? coverImageUrl,
    bool? isOnline,
    DateTime? createdAt,
    DateTime? lastUpdated,
    DateTime? lastActive,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      isOnline: isOnline ?? this.isOnline,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  /// Safely parse a Firestore Timestamp or raw value to DateTime.
  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  @override
  String toString() {
    return 'UserModel(uid: $uid, username: $username, email: $email)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
