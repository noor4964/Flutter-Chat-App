import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/services/auth_service.dart';
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/models/chat_model.dart';
import 'chat_screen.dart';
import 'package:flutter_chat_app/views/profile/profile_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';
import 'package:flutter_chat_app/views/pending_requests_screen.dart'; // Import the PendingRequestsScreen

class ChatListScreen extends StatefulWidget {
  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  final User? user = FirebaseAuth.instance.currentUser;
  Set<String> _selectedChats = Set<String>();

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Center(child: Text('User not authenticated.'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat List'),
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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PendingRequestsScreen()),
              );
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
            DrawerHeader(
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
              leading: Icon(Icons.chat),
              title: Text('Chats'),
              onTap: () {
                Navigator.pop(context); // Close the drawer
              },
            ),
            ListTile(
              leading: Icon(Icons.person),
              title: Text('Profile'),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfileScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Settings'),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<Chat>>(
        stream: _chatService.getUserChats(user!.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            print('Error: ${snapshot.error}');
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No chats available.'));
          }
          var chats = snapshot.data!;
          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              var chat = chats[index];
              bool isSelected = _selectedChats.contains(chat.id);
              return GestureDetector(
                onLongPress: () {
                  setState(() {
                    if (isSelected) {
                      _selectedChats.remove(chat.id);
                    } else {
                      _selectedChats.add(chat.id);
                    }
                  });
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  color: isSelected ? Colors.grey[300] : Colors.white,
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person),
                    ),
                    title: Text(
                      chat.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(chat.lastMessage),
                    trailing: isSelected
                        ? PopupMenuButton<String>(
                            onSelected: (String result) {
                              setState(() {
                                _selectedChats.remove(chat.id);
                                // Handle the selected action
                                switch (result) {
                                  case 'Archive':
                                    // Handle Archive action
                                    break;
                                  case 'Mute':
                                    // Handle Mute action
                                    break;
                                  case 'Block':
                                    // Handle Block action
                                    break;
                                  case 'Delete':
                                    if (user != null) {
                                      _chatService.deleteChat(chat.id, user!.uid);
                                    }
                                    break;
                                }
                              });
                            },
                            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                              const PopupMenuItem<String>(
                                value: 'Archive',
                                child: Text('Archive'),
                              ),
                              const PopupMenuItem<String>(
                                value: 'Mute',
                                child: Text('Mute'),
                              ),
                              const PopupMenuItem<String>(
                                value: 'Block',
                                child: Text('Block'),
                              ),
                              const PopupMenuItem<String>(
                                value: 'Delete',
                                child: Text('Delete'),
                              ),
                            ],
                          )
                        : null,
                    onTap: () {
                      if (!isSelected) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(chatId: chat.id),
                          ),
                        );
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}