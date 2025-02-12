import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/views/chat/chat_list_screen.dart';
import 'package:flutter_chat_app/views/profile/profile_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/views/pending_requests_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginScreen(),
        '/chatList': (context) => ChatListScreen(),
        '/profile': (context) => ProfileScreen(),
        '/settings': (context) => SettingsScreen(),
        '/userList': (context) => UserListScreen(),
        '/pendingRequests': (context) => PendingRequestsScreen(),
      },
    );
  }
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
      QuerySnapshot chatSnapshot = await FirebaseFirestore.instance
          .collection('chats')
          .where('userIds', arrayContains: currentUserId) // 🔥 Fetch only chats of the current user
          .get();

      Set<String> userIds = {}; // Use a Set to avoid duplicates
      for (var doc in chatSnapshot.docs) {
        List<dynamic> chatUsers = doc['userIds'];
        userIds.addAll(chatUsers.map((e) => e.toString())); // Ensure all are strings
      }
      userIds.remove(currentUserId); // Remove self from the list

      return userIds.toList(); // Convert Set back to List
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
      QuerySnapshot userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('uid', whereIn: chatUserIds) // 🔥 Fetch only relevant users
          .get();

      return userSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    } catch (e) {
      print("❌ Error fetching chat users: $e");
      return [];
    }
  }

  // Send connection request
  Future<void> sendConnectionRequest(String receiverId) async {
    String senderId = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance.collection('connections').add({
      'senderId': senderId,
      'receiverId': receiverId,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Accept connection request
  Future<void> acceptConnection(String connectionId) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("❌ User not logged in!");
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('connections').doc(connectionId).update({
        'status': 'accepted',
      });
      print("✅ Connection accepted!");
    } catch (e) {
      print("❌ Error accepting connection: $e");
    }
  }

  // Fetch pending connection requests
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    String userId = FirebaseAuth.instance.currentUser!.uid;
    
    QuerySnapshot query = await FirebaseFirestore.instance
        .collection('connections')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .get();

    return query.docs.map((doc) {
      var data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id; // Include the document ID
      return data;
    }).toList();
  }
}
