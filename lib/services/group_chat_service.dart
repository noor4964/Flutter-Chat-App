import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';

/// Service handling all group chat operations:
/// creation, member management, admin promotion, and group info updates.
class GroupChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool get _isWindowsWithoutFirebase =>
      PlatformHelper.isWindows && !FirebaseConfig.isFirebaseEnabledOnWindows;

  // ─── Group Creation ─────────────────────────────────────────────────

  /// Create a new group chat. Returns the new chat document ID.
  Future<String?> createGroupChat({
    required String groupName,
    required List<String> memberIds,
    String? groupDescription,
    String? groupImageUrl,
  }) async {
    if (_isWindowsWithoutFirebase) {
      print('Group chat creation skipped on Windows');
      return null;
    }

    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return null;

    // Ensure creator is in the member list
    final allMembers = <String>{currentUserId, ...memberIds}.toList();

    // Build member roles map: creator is admin, others are members
    final memberRoles = <String, String>{};
    for (final uid in allMembers) {
      memberRoles[uid] = uid == currentUserId ? 'admin' : 'member';
    }

    try {
      final chatRef = _firestore.collection('chats').doc();

      final chatData = {
        'isGroup': true,
        'groupName': groupName,
        'groupDescription': groupDescription ?? '',
        'groupImageUrl': groupImageUrl ?? '',
        'createdBy': currentUserId,
        'admins': [currentUserId],
        'memberRoles': memberRoles,
        'userIds': allMembers,
        'lastMessage': 'Group created',
        'lastMessageSenderId': currentUserId,
        'lastMessageReadBy': [currentUserId],
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'typing': {},
        'isDeleted': false,
      };

      // Create chat document first so security rules can validate the messages subcollection write
      await chatRef.set(chatData);

      // Then add the system message (now the parent doc exists for the get() rule check)
      await chatRef.collection('messages').add({
        'content': 'Group "$groupName" was created',
        'senderId': currentUserId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'system',
        'readBy': [currentUserId],
      });

      print('✅ Group chat created: ${chatRef.id}');
      return chatRef.id;
    } catch (e) {
      print('❌ Error creating group chat: $e');
      return null;
    }
  }

  // ─── Member Management ──────────────────────────────────────────────

  /// Add a member to an existing group chat. Only admins can add members.
  Future<bool> addMember(String chatId, String newMemberId) async {
    if (_isWindowsWithoutFirebase) return false;

    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return false;

    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return false;

      final data = chatDoc.data()!;
      final admins = List<String>.from(data['admins'] ?? []);
      if (!admins.contains(currentUserId)) {
        print('⚠️ Only admins can add members');
        return false;
      }

      // Fetch the new member's username for the system message
      String memberName = 'A user';
      try {
        final userDoc =
            await _firestore.collection('users').doc(newMemberId).get();
        memberName = userDoc.data()?['username'] ?? 'A user';
      } catch (_) {}

      final batch = _firestore.batch();

      batch.update(_firestore.collection('chats').doc(chatId), {
        'userIds': FieldValue.arrayUnion([newMemberId]),
        'memberRoles.$newMemberId': 'member',
      });

      final msgRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc();
      batch.set(msgRef, {
        'content': '$memberName was added to the group',
        'senderId': 'system',
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'system',
        'readBy': [currentUserId],
      });

      await batch.commit();
      return true;
    } catch (e) {
      print('❌ Error adding member: $e');
      return false;
    }
  }

  /// Remove a member from the group.
  /// Admins can remove members; members can remove themselves (leave).
  Future<bool> removeMember(String chatId, String memberId) async {
    if (_isWindowsWithoutFirebase) return false;

    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return false;

    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return false;

      final data = chatDoc.data()!;
      final admins = List<String>.from(data['admins'] ?? []);

      // Only admins can remove others; anyone can remove themselves (leave)
      if (memberId != currentUserId && !admins.contains(currentUserId)) {
        print('⚠️ Only admins can remove members');
        return false;
      }

      // Fetch the member's username for the system message
      String memberName = 'A user';
      try {
        final userDoc =
            await _firestore.collection('users').doc(memberId).get();
        memberName = userDoc.data()?['username'] ?? 'A user';
      } catch (_) {}

      final batch = _firestore.batch();
      final chatRef = _firestore.collection('chats').doc(chatId);

      batch.update(chatRef, {
        'userIds': FieldValue.arrayRemove([memberId]),
        'memberRoles.$memberId': FieldValue.delete(),
        if (admins.contains(memberId))
          'admins': FieldValue.arrayRemove([memberId]),
      });

      final isLeaving = memberId == currentUserId;
      final msgRef = chatRef.collection('messages').doc();
      batch.set(msgRef, {
        'content': isLeaving
            ? '$memberName left the group'
            : '$memberName was removed from the group',
        'senderId': 'system',
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'system',
        'readBy': [currentUserId],
      });

      await batch.commit();
      return true;
    } catch (e) {
      print('❌ Error removing member: $e');
      return false;
    }
  }

  /// Promote a member to admin. Only admins can promote.
  Future<bool> promoteToAdmin(String chatId, String memberId) async {
    if (_isWindowsWithoutFirebase) return false;

    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return false;

    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      final admins = List<String>.from(chatDoc.data()?['admins'] ?? []);
      if (!admins.contains(currentUserId)) return false;

      await _firestore.collection('chats').doc(chatId).update({
        'admins': FieldValue.arrayUnion([memberId]),
        'memberRoles.$memberId': 'admin',
      });
      return true;
    } catch (e) {
      print('❌ Error promoting member: $e');
      return false;
    }
  }

  /// Demote an admin to regular member. Only the group creator can demote.
  Future<bool> demoteAdmin(String chatId, String memberId) async {
    if (_isWindowsWithoutFirebase) return false;

    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return false;

    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      final createdBy = chatDoc.data()?['createdBy'];
      if (createdBy != currentUserId) return false;

      await _firestore.collection('chats').doc(chatId).update({
        'admins': FieldValue.arrayRemove([memberId]),
        'memberRoles.$memberId': 'member',
      });
      return true;
    } catch (e) {
      print('❌ Error demoting admin: $e');
      return false;
    }
  }

  // ─── Group Info ─────────────────────────────────────────────────────

  /// Update group info (name, description, image).
  Future<bool> updateGroupInfo(
    String chatId, {
    String? groupName,
    String? groupDescription,
    String? groupImageUrl,
  }) async {
    if (_isWindowsWithoutFirebase) return false;

    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return false;

    try {
      final updates = <String, dynamic>{};
      if (groupName != null) updates['groupName'] = groupName;
      if (groupDescription != null) {
        updates['groupDescription'] = groupDescription;
      }
      if (groupImageUrl != null) updates['groupImageUrl'] = groupImageUrl;
      if (updates.isEmpty) return false;

      await _firestore.collection('chats').doc(chatId).update(updates);
      return true;
    } catch (e) {
      print('❌ Error updating group info: $e');
      return false;
    }
  }

  // ─── Queries ────────────────────────────────────────────────────────

  /// Get group members with their profile info.
  Future<List<Map<String, dynamic>>> getGroupMembers(String chatId) async {
    if (_isWindowsWithoutFirebase) return [];

    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return [];

      final data = chatDoc.data()!;
      final userIds = List<String>.from(data['userIds'] ?? []);
      final memberRoles =
          Map<String, dynamic>.from(data['memberRoles'] ?? {});

      final members = <Map<String, dynamic>>[];

      // Batch fetch user profiles (max 10 per `whereIn` query)
      for (var i = 0; i < userIds.length; i += 10) {
        final chunk = userIds.sublist(i, (i + 10).clamp(0, userIds.length));
        final usersSnapshot = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final userDoc in usersSnapshot.docs) {
          final userData = userDoc.data();
          members.add({
            'uid': userDoc.id,
            'username': userData['username'] ?? 'Unknown',
            'profileImageUrl': userData['profileImageUrl'] ?? '',
            'isOnline': userData['isOnline'] ?? false,
            'role': memberRoles[userDoc.id] ?? 'member',
          });
        }
      }

      // Sort: admins first, then alphabetically
      members.sort((a, b) {
        if (a['role'] == 'admin' && b['role'] != 'admin') return -1;
        if (a['role'] != 'admin' && b['role'] == 'admin') return 1;
        return (a['username'] as String)
            .compareTo(b['username'] as String);
      });

      return members;
    } catch (e) {
      print('❌ Error fetching group members: $e');
      return [];
    }
  }

  /// Stream group chat document for real-time updates.
  Stream<DocumentSnapshot> streamGroupChat(String chatId) {
    return _firestore.collection('chats').doc(chatId).snapshots();
  }
}
