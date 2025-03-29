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
            '⚠️ Found existing logged in user, signing out first to avoid state conflicts');
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
  Future<void> sendConnectionRequest(String receiverId) async {
    String senderId = _auth.currentUser!.uid;

    await _firestore.collection('connections').add({
      'senderId': senderId,
      'receiverId': receiverId,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
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

      // Create a chat document for both users
      DocumentReference chatRef = _firestore.collection('chats').doc();
      await chatRef.set({
        'adminId': _auth.currentUser!.uid,
        'chatPhotoUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
        'isGroupChat': false,
        'lastMessage': '',
        'name': '',
        'typing': {},
        'userIds': [_auth.currentUser!.uid, receiverId],
      });

      print("✅ Chat document created with ID: ${chatRef.id}");

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
}
