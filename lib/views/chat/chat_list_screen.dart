import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/services/auth_service.dart';
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/views/profile/profile_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';
import 'package:flutter_chat_app/views/pending_requests_screen.dart';
import 'chat_screen.dart';
import 'dart:async';

class ChatListScreen extends StatefulWidget {
  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  final User? user = FirebaseAuth.instance.currentUser;
  late StreamController<QuerySnapshot> _chatListController;

  @override
  void initState() {
    super.initState();
    _chatListController = StreamController<QuerySnapshot>();
    _fetchChatList(); // Initial fetch
  }

  // Fetch latest chat list and add to stream
  void _fetchChatList() async {
    FirebaseFirestore.instance
        .collection('chats')
        .where('userIds', arrayContains: FirebaseAuth.instance.currentUser!.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      _chatListController.add(snapshot);
    });
  }

  @override
  void dispose() {
    _chatListController.close();
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
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(otherUserId).get();
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
    _fetchChatList(); // 🔄 Refresh chat list when coming back from ChatScreen
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
            onPressed: () async {
              await AuthService().signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginScreen()),
              );
            },
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
                Navigator.pop(context); // Close the drawer
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
      body: StreamBuilder<QuerySnapshot>(
        stream: _chatListController.stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var chatDocs = snapshot.data!.docs;
          Set<String> displayedUsers = {}; // Track displayed users

          return ListView.builder(
            itemCount: chatDocs.length,
            itemBuilder: (context, index) {
              var chatData = chatDocs[index].data() as Map<String, dynamic>;
              String chatId = chatDocs[index].id;
              List<String> userIds = List<String>.from(chatData['userIds'] ?? []);

              return FutureBuilder<String>(
                future: fetchChatPartnerName(userIds),
                builder: (context, nameSnapshot) {
                  if (!nameSnapshot.hasData) {
                    return const ListTile(title: Text("Loading..."));
                  }

                  String chatName = nameSnapshot.data!;
                  if (displayedUsers.contains(chatName)) {
                    return const SizedBox.shrink(); // Skip duplicate users
                  }
                  displayedUsers.add(chatName);

                  return ListTile(
                    title: Text(chatName),
                    subtitle: Text(chatData['lastMessage'] ?? "Tap to open chat"),
                    trailing: Text(
                      chatData['createdAt'] != null
                          ? DateTime.fromMillisecondsSinceEpoch(
                              (chatData['createdAt'] as Timestamp).millisecondsSinceEpoch,
                            ).toLocal().toString().split(' ')[0] // ✅ Show formatted date
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
                        _fetchChatList(); // 🔄 Refresh manually after returning
                      }
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
