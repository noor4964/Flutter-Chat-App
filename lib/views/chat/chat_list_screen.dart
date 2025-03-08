import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/views/profile/profile_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';
import 'package:flutter_chat_app/views/pending_requests_screen.dart';
import 'chat_screen.dart';
import 'dart:async';
import 'package:flutter_chat_app/services/navigator_observer.dart';

class ChatListScreen extends StatefulWidget {
  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  final User? user = FirebaseAuth.instance.currentUser;
  late StreamSubscription<QuerySnapshot> _chatsSubscription;
  QuerySnapshot? _lastSnapshot; // Holds the most recent data

  @override
  void initState() {
    super.initState();
    _fetchChatList();
  }

  // Fetch latest chat list and store it locally
  void _fetchChatList() async {
    print("Fetching chat list...");

    await _chatsSubscription?.cancel();

    _chatsSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('userIds', arrayContains: FirebaseAuth.instance.currentUser!.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      print("Chat list fetched: ${snapshot.docs.length} documents");
      setState(() {
        _lastSnapshot = snapshot; // Save latest snapshot
      });
    }, onError: (error) {
      print("Error fetching chat list: $error");
    });
  }

  @override
  void dispose() {
    print("Disposing ChatListScreen...");
    _chatsSubscription?.cancel();
    super.dispose();
  }

  // Fetch chat partner's name
  Future<String> fetchChatPartnerName(List<String> userIds) async {
    String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    String otherUserId = userIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => "Unknown",
    );

    if (otherUserId == "Unknown") return "Unknown";

    try {
      var userDoc =
          await FirebaseFirestore.instance.collection('users').doc(otherUserId).get();
      if (userDoc.exists) {
        return userDoc.data()?['username'] ?? 'Unknown';
      }
    } catch (e) {
      debugPrint("Error fetching user: $e");
    }
    return "Unknown";
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print("Dependencies changed, registering observer for navigation...");

    // Register callback with NavigatorObserver
    final observer = Navigator.of(context).widget.observers
        .firstWhere((obs) => obs is MyNavigatorObserver) as MyNavigatorObserver;
    observer.setCallback(() {
      setState(() {
        _fetchChatList(); // 🔄 Refresh chat list on return
      });
    });
  }

  Future<void> signOutUser() async {
    print("Signing out user...");
    await _chatsSubscription?.cancel();
    await FirebaseAuth.instance.signOut();
    print("✅ User signed out successfully");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Center(child: Text('User not authenticated.'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserListScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PendingRequestsScreen()),
              );
              _fetchChatList(); // 🔄 Refresh chat list after returning
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: signOutUser,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.deepPurple,
              ),
              child: Text(
                'Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('Chats'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfileScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: _lastSnapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _lastSnapshot!.docs.length,
              itemBuilder: (context, index) {
                var chatData = _lastSnapshot!.docs[index].data() as Map<String, dynamic>;
                String chatId = _lastSnapshot!.docs[index].id;
                List<String> userIds = List<String>.from(chatData['userIds'] ?? []);

                return FutureBuilder<String>(
                  future: fetchChatPartnerName(userIds),
                  builder: (context, nameSnapshot) {
                    if (nameSnapshot.hasError) {
                      return const ListTile(title: Text("Error loading name"));
                    }
                    if (!nameSnapshot.hasData) {
                      return const ListTile(title: Text("Loading..."));
                    }

                    String chatName = nameSnapshot.data!;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey[300],
                          child: Text(
                            chatName.isNotEmpty ? chatName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(chatName),
                        subtitle: Text(chatData['lastMessage'] ?? "Tap to open chat"),
                        trailing: Text(
                          chatData['createdAt'] != null
                              ? DateTime.fromMillisecondsSinceEpoch(
                                      (chatData['createdAt'] as Timestamp)
                                          .millisecondsSinceEpoch)
                                  .toLocal()
                                  .toString()
                                  .split(' ')[0]
                              : '',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        onTap: () async {
                          bool? shouldRefresh = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(chatId: chatId),
                            ),
                          );
                          if (shouldRefresh == true) {
                            _fetchChatList();
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UserListScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
