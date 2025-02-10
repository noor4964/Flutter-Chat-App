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
                    leading: FutureBuilder<bool>(
                      future: _chatService.isUserMuted(chat.id, user!.uid),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const CircleAvatar(
                            child: Icon(Icons.person),
                          );
                        }
                        bool isMuted = snapshot.data!;
                        return CircleAvatar(
                          child: Icon(
                            isMuted ? Icons.volume_off : Icons.person,
                          ),
                        );
                      },
                    ),
                    title: Text(
                      chat.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(chat.lastMessage),
                    trailing: isSelected
                        ? FutureBuilder<bool>(
                            future: _chatService.isUserBlocked(chat.id, user!.uid),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return CircularProgressIndicator();
                              }
                              bool isBlocked = snapshot.data!;
                              return PopupMenuButton<String>(
                                onSelected: (String result) {
                                  setState(() {
                                    _selectedChats.remove(chat.id);
                                    // Handle the selected action
                                    switch (result) {
                                      case 'Archive':
                                        // Handle Archive action
                                        break;
                                      case 'Mute':
                                        _showMuteOptions(context, chat.id, user!.uid);
                                        break;
                                      case 'Block':
                                        if (isBlocked) {
                                          _chatService.unblockUser(chat.id, user!.uid);
                                        } else {
                                          _chatService.blockUser(chat.id, user!.uid);
                                        }
                                        break;
                                      case 'Delete':
                                        _chatService.deleteChat(chat.id, user!.uid);
                                        break;
                                    }
                                  });
                                },
                                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'Archive',
                                    child: Text('Archive'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'Mute',
                                    child: FutureBuilder<bool>(
                                      future: _chatService.isUserMuted(chat.id, user!.uid),
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData) {
                                          return const Text('Mute');
                                        }
                                        bool isMuted = snapshot.data!;
                                        return Text(isMuted ? 'Unmute' : 'Mute');
                                      },
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'Block',
                                    child: Text(isBlocked ? 'Unblock' : 'Block'),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'Delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              );
                            },
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

  void _showMuteOptions(BuildContext context, String chatId, String userId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Mute Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text('For 15 minutes'),
                onTap: () {
                  _muteUser(chatId, userId, Duration(minutes: 15));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('For 1 hour'),
                onTap: () {
                  _muteUser(chatId, userId, Duration(hours: 1));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('For 8 hours'),
                onTap: () {
                  _muteUser(chatId, userId, Duration(hours: 8));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('For 24 hours'),
                onTap: () {
                  _muteUser(chatId, userId, Duration(hours: 24));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('Until I change it'),
                onTap: () {
                  _muteUser(chatId, userId, Duration(days: 365 * 100)); // Effectively forever
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _muteUser(String chatId, String userId, Duration duration) {
    DateTime muteUntil = DateTime.now().add(duration);
    _chatService.muteUser(chatId, userId, muteUntil);
  }
}