import 'dart:async';
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
import 'package:flutter_chat_app/services/navigator_observer.dart';

class ChatListScreen extends StatefulWidget {
  final bool isDesktop;
  final Function(String chatId, String chatName)? onChatSelected;

  const ChatListScreen({
    Key? key,
    this.isDesktop = false,
    this.onChatSelected,
  }) : super(key: key);

  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  final User? user = FirebaseAuth.instance.currentUser;
  StreamSubscription<QuerySnapshot>? _chatsSubscription;
  QuerySnapshot? _lastSnapshot; // Holds the most recent data
  String? _selectedChatId;

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

  // Fetch chat partner's name and profile picture URL
  Future<Map<String, String>> fetchChatPartnerInfo(List<String> userIds) async {
    String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    String otherUserId = userIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => "Unknown",
    );

    if (otherUserId == "Unknown")
      return {"name": "Unknown", "profileImageUrl": ""};

    try {
      var userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(otherUserId)
          .get();
      if (userDoc.exists) {
        return {
          "name": userDoc.data()?['username'] ?? 'Unknown',
          "profileImageUrl": userDoc.data()?['profileImageUrl'] ?? ''
        };
      }
    } catch (e) {
      debugPrint("Error fetching user: $e");
    }
    return {"name": "Unknown", "profileImageUrl": ""};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print("Dependencies changed, registering observer for navigation...");

    // Only register navigation observer if not in desktop mode
    if (!widget.isDesktop) {
      // Register callback with NavigatorObserver
      final observer = Navigator.of(context)
              .widget
              .observers
              .firstWhere((obs) => obs is MyNavigatorObserver)
          as MyNavigatorObserver;
      observer.setCallback(() {
        setState(() {
          _fetchChatList(); // 🔄 Refresh chat list on return
        });
      });
    }
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
      appBar: widget.isDesktop
          ? AppBar(
              title: const Text('Conversations'),
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
                      MaterialPageRoute(
                          builder: (context) => PendingRequestsScreen()),
                    );
                    _fetchChatList();
                  },
                ),
              ],
            )
          : AppBar(
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
                      MaterialPageRoute(
                          builder: (context) => PendingRequestsScreen()),
                    );
                    _fetchChatList();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: signOutUser,
                ),
              ],
            ),
      drawer: widget.isDesktop
          ? null
          : Drawer(
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
                        MaterialPageRoute(
                            builder: (context) => ProfileScreen()),
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
                        MaterialPageRoute(
                            builder: (context) => SettingsScreen()),
                      );
                    },
                  ),
                  if (widget.isDesktop)
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Logout'),
                      onTap: () {
                        Navigator.pop(context);
                        signOutUser();
                      },
                    ),
                ],
              ),
            ),
      body: Column(
        children: [
          if (widget.isDesktop)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (context) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.person),
                              title: const Text('Profile'),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => ProfileScreen()),
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
                                  MaterialPageRoute(
                                      builder: (context) => SettingsScreen()),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.logout),
                              title: const Text('Logout'),
                              onTap: () {
                                Navigator.pop(context);
                                signOutUser();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search conversations',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 8.0),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _fetchChatList,
                  ),
                ],
              ),
            ),
          Expanded(
            child: _lastSnapshot == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _lastSnapshot!.docs.length,
                    itemBuilder: (context, index) {
                      var chatData = _lastSnapshot!.docs[index].data()
                          as Map<String, dynamic>;
                      String chatId = _lastSnapshot!.docs[index].id;
                      List<String> userIds =
                          List<String>.from(chatData['userIds'] ?? []);

                      return FutureBuilder<Map<String, String>>(
                        future: fetchChatPartnerInfo(userIds),
                        builder: (context, infoSnapshot) {
                          if (infoSnapshot.hasError) {
                            return const ListTile(
                                title: Text("Error loading info"));
                          }
                          if (!infoSnapshot.hasData) {
                            return const ListTile(title: Text("Loading..."));
                          }

                          String chatName = infoSnapshot.data!["name"]!;
                          String profileImageUrl =
                              infoSnapshot.data!["profileImageUrl"]!;
                          bool isRead = chatData['lastMessageReadBy']
                                  ?.contains(user!.uid) ??
                              false;
                          bool isSelected =
                              widget.isDesktop && chatId == _selectedChatId;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 16),
                            color: isSelected
                                ? Colors.deepPurple.withOpacity(0.1)
                                : null,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: profileImageUrl.isNotEmpty
                                    ? NetworkImage(profileImageUrl)
                                    : null,
                                backgroundColor: Colors.grey[300],
                                child: profileImageUrl.isEmpty
                                    ? Text(
                                        chatName.isNotEmpty
                                            ? chatName[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                            color: Colors.white),
                                      )
                                    : null,
                              ),
                              title: Text(
                                chatName,
                                style: TextStyle(
                                  fontWeight: isRead
                                      ? FontWeight.normal
                                      : FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                chatData['lastMessage'] ?? "Tap to open chat",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                chatData['createdAt'] != null
                                    ? DateTime.fromMillisecondsSinceEpoch(
                                            (chatData['createdAt'] as Timestamp)
                                                .millisecondsSinceEpoch)
                                        .toLocal()
                                        .toString()
                                        .split(' ')[0]
                                    : '',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                              onTap: () async {
                                if (widget.isDesktop &&
                                    widget.onChatSelected != null) {
                                  setState(() {
                                    _selectedChatId = chatId;
                                  });
                                  widget.onChatSelected!(chatId, chatName);
                                } else {
                                  bool? shouldRefresh = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ChatScreen(chatId: chatId),
                                    ),
                                  );
                                  if (shouldRefresh == true) {
                                    _fetchChatList();
                                  }
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
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
