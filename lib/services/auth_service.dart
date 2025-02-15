import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // StreamController to manually trigger UI updates
  final StreamController<bool> chatListController = StreamController<bool>.broadcast();

  // Sign in with email and password
  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(email: email, password: password);
      print('✅ User signed in: ${result.user?.uid}');
      return result.user;
    } on FirebaseAuthException catch (e) {
      print('❌ Sign-in error: ${e.code} - ${e.message}');
      return null;
    }
  }

  // Register with email and password
  Future<User?> registerWithEmailAndPassword(String username, String email, String password, String gender) async {
    try {
      // 1️⃣ Create user in Firebase Authentication
      UserCredential result = await _auth.createUserWithEmailAndPassword(email: email, password: password);
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
      await _auth.signOut();
      print('✅ User signed out successfully');
    } on FirebaseAuthException catch (e) {
      print('❌ Sign-out error: ${e.code} - ${e.message}');
    }
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

      return userSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
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
  Future<void> acceptConnectionRequest(String requestId, String receiverId) async {
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
        .map((snapshot) =>
            snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList());
  }
}
