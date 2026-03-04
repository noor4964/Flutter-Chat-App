import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Flag to check if we're on Windows with Firebase disabled
  bool get _isWindowsWithoutFirebase =>
      PlatformHelper.isWindows && !FirebaseConfig.isFirebaseEnabledOnWindows;

  // Flag to check if we're on web
  bool get _isWeb => kIsWeb;

  // StreamController to manually trigger UI updates
  final StreamController<bool> chatListController =
      StreamController<bool>.broadcast();

  // Get current user stream
  Stream<User?> get userStream {
    if (_isWindowsWithoutFirebase) {
      // Return null stream for Windows - safer than trying to create a mock User
      return Stream.value(null);
    }

    return FirebaseAuth.instance.authStateChanges().handleError((error) {
      print('Error in auth state stream: $error');
      return null;
    });
  }

  // Sign in with email and password
  Future<User?> signInWithEmailAndPassword(
      String email, String password) async {
    if (_isWindowsWithoutFirebase) {
      // Return mock user for Windows
      print(
          '⚠️ Windows detected with Firebase disabled, using mock authentication');
      await Future.delayed(
          const Duration(seconds: 1)); // Simulate network delay
      return FirebaseAuth.instance.currentUser;
    }

    try {
      print(
          '👤 Attempting to sign in with email: $email on platform: ${_isWeb ? "Web" : "Native"}');

      // Force signout before attempting signin to clear any stale state
      if (_auth.currentUser != null) {
        print(
            '⚠️ Warning: A user is already signed in, signing out before new sign in');
        await _auth.signOut();
      }

      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      print('✅ Sign in successful for user: ${credential.user?.uid}');

      // Update user's online status
      if (credential.user != null) {
        try {
          await _firestore
              .collection('users')
              .doc(credential.user!.uid)
              .update({
            'isOnline': true,
            'lastActive': FieldValue.serverTimestamp(),
          });
          print('✅ Updated online status for user: ${credential.user!.uid}');

          // Verify the user is still logged in
          final currentUser = _auth.currentUser;
          if (currentUser != null) {
            print(
                '✅ Verified user is still authenticated after online status update');
          } else {
            print(
                '❌ Error: User authentication state was lost after online status update');
          }
        } catch (e) {
          // If updating online status fails, log but don't prevent login
          print('⚠️ Warning: Could not update online status: $e');
        }
      }

      return credential.user;
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Unexpected error during sign in: $e');
      rethrow;
    }
  }

  // Register with email and password
  Future<User?> registerWithEmailAndPassword(
      String username, String email, String password, String gender) async {
    try {
      // 1️⃣ Create user in Firebase Authentication
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;

      if (user == null) {
        print('❌ User is null after registration');
        return null;
      }

      print('✅ Registered User UID: ${user.uid}'); // Debugging

      // 2️⃣ Store user data in Firestore
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'username': username,
        'email': email,
        'gender': gender,
        'createdAt': FieldValue.serverTimestamp(),
        'isOnline': true, // Set initial online status to true
      });

      return user;
    } on FirebaseAuthException catch (e) {
      print('❌ Error: ${e.message}');
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        try {
          _updateUserOnlineStatus(user.uid, false);
        } catch (e) {
          // If updating online status fails, log but don't prevent sign out
          print(
              '⚠️ Warning: Could not update online status during sign out: $e');
        }
      }
      await _auth.signOut();
      print('✅ User signed out successfully');
    } on FirebaseAuthException catch (e) {
      print('❌ Sign-out error: ${e.code} - ${e.message}');
      throw e; // Rethrow to let UI handle the error
    }
  }

  // Update user's online status
  void _updateUserOnlineStatus(String userId, bool isOnline) {
    _firestore.collection('users').doc(userId).update({
      'isOnline': isOnline,
    });
  }

  // Get current user
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Check if user is authenticated
  bool isUserLoggedIn() {
    return _auth.currentUser != null;
  }

  // Get chat user IDs
  Future<List<String>> getChatUserIds(String currentUserId) async {
    try {
      QuerySnapshot chatSnapshot = await _firestore
          .collection('chats')
          .where('userIds', arrayContains: currentUserId)
          .get();

      Set<String> userIds = {};
      for (var doc in chatSnapshot.docs) {
        List<dynamic> chatUsers = doc['userIds'];
        userIds.addAll(chatUsers.map((e) => e.toString()));
      }
      userIds.remove(currentUserId);

      return userIds.toList();
    } catch (e) {
      print("❌ Error fetching chat user IDs: $e");
      return [];
    }
  }

  // Get chat users
  Future<List<Map<String, dynamic>>> getChatUsers(String currentUserId) async {
    List<String> chatUserIds = await getChatUserIds(currentUserId);

    if (chatUserIds.isEmpty) return [];

    try {
      QuerySnapshot userSnapshot = await _firestore
          .collection('users')
          .where('uid', whereIn: chatUserIds)
          .get();

      return userSnapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print("❌ Error fetching chat users: $e");
      return [];
    }
  }

  // Send connection request
  Future<String?> sendConnectionRequest(String receiverId) async {
    String senderId = _auth.currentUser!.uid;

    // Check if a request already exists
    QuerySnapshot existingRequests = await _firestore
        .collection('connections')
        .where('senderId', isEqualTo: senderId)
        .where('receiverId', isEqualTo: receiverId)
        .where('status', isEqualTo: 'pending')
        .get();

    // If request already exists, return its ID
    if (existingRequests.docs.isNotEmpty) {
      return existingRequests.docs.first.id;
    }

    // Otherwise create a new request
    DocumentReference docRef = await _firestore.collection('connections').add({
      'senderId': senderId,
      'receiverId': receiverId,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  // Accept connection request and create chat
  Future<void> acceptConnectionRequest(
      String requestId, String receiverId) async {
    print("Accepting connection request...");
    try {
      await _firestore.collection('connections').doc(requestId).update({
        'status': 'accepted',
      });
      print("✅ Connection request accepted.");

      // Check if a chat already exists between these two users
      String currentUserId = _auth.currentUser!.uid;
      final existingChats = await _firestore
          .collection('chats')
          .where('userIds', arrayContains: currentUserId)
          .get();

      bool chatExists = existingChats.docs.any((doc) {
        List<String> userIds = List<String>.from(doc['userIds']);
        return userIds.contains(receiverId);
      });

      if (!chatExists) {
        // Create a chat document for both users
        DocumentReference chatRef = _firestore.collection('chats').doc();
        await chatRef.set({
          'adminId': currentUserId,
          'chatPhotoUrl': '',
          'createdAt': FieldValue.serverTimestamp(),
          'isGroupChat': false,
          'lastMessage': '',
          'name': '',
          'typing': {},
          'userIds': [currentUserId, receiverId],
        });
        print("✅ Chat document created with ID: ${chatRef.id}");
      } else {
        print("✅ Chat already exists, skipping creation.");
      }

      // Notify chat list to update
      chatListController.add(true);
    } catch (e) {
      print("❌ Error accepting connection request: $e");
    }
  }

  // Fetch pending connection requests
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    String userId = _auth.currentUser!.uid;

    QuerySnapshot query = await _firestore
        .collection('connections')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .get();

    return query.docs.map((doc) {
      var data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  // Real-time chat list updates
  Stream<List<Map<String, dynamic>>> getChatList() {
    String currentUserId = _auth.currentUser!.uid;

    return _firestore
        .collection('chats')
        .where('userIds', arrayContains: currentUserId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .toList());
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    if (_isWindowsWithoutFirebase) {
      print(
          '⚠️ Windows detected with Firebase disabled, simulating password reset');
      await Future.delayed(
          const Duration(seconds: 1)); // Simulate network delay
      return;
    }

    try {
      print('📧 Attempting to send password reset email to: $email');
      await _auth.sendPasswordResetEmail(email: email.trim());
      print('✅ Password reset email sent successfully to: $email');
    } on FirebaseAuthException catch (e) {
      print(
          '❌ Firebase Auth Error when sending password reset: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Unexpected error during password reset: $e');
      rethrow;
    }
  }

  // Verify password reset code and set new password
  Future<void> confirmPasswordReset(String code, String newPassword) async {
    if (_isWindowsWithoutFirebase) {
      print(
          '⚠️ Windows detected with Firebase disabled, simulating password reset confirmation');
      await Future.delayed(
          const Duration(seconds: 1)); // Simulate network delay
      return;
    }

    try {
      print('🔑 Attempting to confirm password reset with code');
      await _auth.confirmPasswordReset(code: code, newPassword: newPassword);
      print('✅ Password reset confirmed successfully');
    } on FirebaseAuthException catch (e) {
      print(
          '❌ Firebase Auth Error when confirming password reset: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Unexpected error during password reset confirmation: $e');
      rethrow;
    }
  }

  // ─── Profile Management ───────────────────────────────────────────────

  /// Fetch the current user's profile data from Firestore.
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (_isWindowsWithoutFirebase) {
      print('⚠️ Windows: returning mock profile');
      return {
        'uid': 'mock-uid',
        'username': 'Windows User',
        'email': 'mock@example.com',
      };
    }

    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      data['uid'] = user.uid;
      return data;
    } catch (e) {
      print('❌ Error fetching user profile: $e');
      rethrow;
    }
  }

  /// Update the current user's profile fields in Firestore.
  ///
  /// [fields] should only contain the changed key-value pairs.
  /// Automatically appends `lastUpdated` server timestamp.
  /// Also syncs `displayName` on the Firebase Auth user if `username` changed.
  Future<void> updateProfile(Map<String, dynamic> fields) async {
    if (_isWindowsWithoutFirebase) {
      print('⚠️ Windows: simulating profile update');
      await Future.delayed(const Duration(milliseconds: 500));
      return;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No authenticated user');

      // Ensure server timestamp is included
      if (!fields.containsKey('lastUpdated')) {
        fields['lastUpdated'] = FieldValue.serverTimestamp();
      }

      print('📝 Updating profile for ${user.uid}: ${fields.keys.join(', ')}');

      await _firestore.collection('users').doc(user.uid).update(fields);

      // Sync displayName on Firebase Auth if username changed
      if (fields.containsKey('username')) {
        await user.updateDisplayName(fields['username'] as String);
      }

      print('✅ Profile updated successfully');
    } on FirebaseException catch (e) {
      print('❌ Firestore error updating profile: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Error updating profile: $e');
      rethrow;
    }
  }

  /// Check if a username is already taken by another user.
  /// Returns `true` if the username is available.
  Future<bool> isUsernameAvailable(String username) async {
    if (_isWindowsWithoutFirebase) return true;

    try {
      final user = _auth.currentUser;
      final query = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return true;
      // Available if the only match is the current user
      return user != null && query.docs.first.id == user.uid;
    } catch (e) {
      print('⚠️ Error checking username availability: $e');
      return true; // Assume available on error to not block the user
    }
  }

  // ─── Account Security ─────────────────────────────────────────────────

  /// Change password for the currently authenticated user.
  /// Requires [currentPassword] for re-authentication and [newPassword] as the new value.
  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    if (_isWindowsWithoutFirebase) {
      print('⚠️ Windows: simulating password change');
      await Future.delayed(const Duration(seconds: 1));
      return;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No authenticated user');
      if (user.email == null) throw Exception('User has no email address');

      print('🔒 Re-authenticating user for password change...');

      // Re-authenticate the user first
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      print('✅ Re-authentication successful, updating password...');

      // Update the password
      await user.updatePassword(newPassword);

      print('✅ Password changed successfully');
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error during password change: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Error changing password: $e');
      rethrow;
    }
  }

  /// Delete the current user's account permanently.
  /// Requires [currentPassword] for re-authentication.
  /// Deletes the Firestore user document, connections, and Firebase Auth account.
  Future<void> deleteAccount(String currentPassword) async {
    if (_isWindowsWithoutFirebase) {
      print('⚠️ Windows: simulating account deletion');
      await Future.delayed(const Duration(seconds: 1));
      return;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No authenticated user');
      if (user.email == null) throw Exception('User has no email address');

      print('🔒 Re-authenticating user for account deletion...');

      // Re-authenticate first
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      print('✅ Re-authentication successful, deleting account data...');

      final uid = user.uid;

      // Delete user's connections (both sent and received)
      final sentConnections = await _firestore
          .collection('connections')
          .where('senderId', isEqualTo: uid)
          .get();
      final receivedConnections = await _firestore
          .collection('connections')
          .where('receiverId', isEqualTo: uid)
          .get();

      final batch = _firestore.batch();
      for (final doc in sentConnections.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in receivedConnections.docs) {
        batch.delete(doc.reference);
      }

      // Delete user document from Firestore
      batch.delete(_firestore.collection('users').doc(uid));

      await batch.commit();
      print('✅ Firestore data deleted');

      // Finally delete the Firebase Auth account
      await user.delete();
      print('✅ Firebase Auth account deleted');
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error during account deletion: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Error deleting account: $e');
      rethrow;
    }
  }
}
