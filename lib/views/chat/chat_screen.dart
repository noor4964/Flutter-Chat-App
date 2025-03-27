import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/models/message_model.dart';
import 'package:flutter_chat_app/widgets/message_bubble.dart';
import 'package:flutter_chat_app/views/user_profile_screen.dart'; // Import UserProfileScreen

class ChatScreen extends StatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final User? user = FirebaseAuth.instance.currentUser;
  String? _chatPersonName;
  String? _chatPersonAvatarUrl;
  bool _chatPersonIsOnline = false;
  Map<String, String> _usernamesCache = {};

  @override
  void initState() {
    super.initState();
    _loadChatPersonDetails();
    _cacheUsernames();
    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadChatPersonDetails() async {
    if (user != null) {
      DocumentSnapshot chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();
      if (chatDoc.exists) {
        List<dynamic> userIds = chatDoc['userIds'];
        String chatPersonId = "";

        for (var id in userIds) {
          if (id != user!.uid) {
            chatPersonId = id;
            break;
          }
        }

        if (chatPersonId.isNotEmpty) {
          DocumentSnapshot userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(chatPersonId)
              .get();
          if (userDoc.exists && mounted) {
            final userData = userDoc.data() as Map<String, dynamic>?;
            setState(() {
              _chatPersonName = userData?['username'];
              _chatPersonAvatarUrl =
                  userData != null && userData.containsKey('profileImageUrl')
                      ? userData['profileImageUrl']
                      : null;
              _chatPersonIsOnline = userData?['isOnline'] ?? false;
            });
            print('Avatar URL: $_chatPersonAvatarUrl'); // Debugging statement
          } else {
            print('User document does not exist');
          }
        } else {
          print('No other user found in the chat');
        }
      } else {
        print('Chat document does not exist');
      }
    }
  }

  Future<void> _cacheUsernames() async {
    if (user != null) {
      DocumentSnapshot chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();
      if (chatDoc.exists) {
        List<dynamic> userIds = chatDoc['userIds'];
        for (String userId in userIds) {
          if (userId != user!.uid) {
            String username = await _chatService.getUsername(userId);
            _usernamesCache[userId] = username;
          }
        }
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    if (user != null) {
      await _chatService.markMessagesAsRead(widget.chatId, user!.uid);
    }
  }

  void _showChatPersonDetails() {
    if (!mounted) return; // Ensure the widget is still mounted
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          profileImageUrl: _chatPersonAvatarUrl ?? '',
          username: _chatPersonName ?? 'Loading...',
          isOnline: _chatPersonIsOnline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(
                context, true); // ✅ Pass `true` to notify ChatListScreen
          },
        ),
        title: Row(
          children: [
            GestureDetector(
              onTap: _showChatPersonDetails,
              child: CircleAvatar(
                backgroundImage: _chatPersonAvatarUrl != null
                    ? NetworkImage(_chatPersonAvatarUrl!)
                    : null,
                child: _chatPersonAvatarUrl == null
                    ? const Icon(Icons.person)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _showChatPersonDetails,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _chatPersonName ?? 'Loading...',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _chatPersonIsOnline ? 'Active now' : 'Offline',
                    style: TextStyle(
                        fontSize: 12,
                        color: _chatPersonIsOnline ? Colors.green : Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              // Handle call action
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              // Handle video call action
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showChatPersonDetails,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: FutureBuilder<void>(
              future: _cacheUsernames(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return StreamBuilder<List<Message>>(
                  stream: _chatService.getMessages(widget.chatId, user!.uid),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var messages = snapshot.data!;
                    return ListView.builder(
                      reverse: true, // Reverse the order of the messages
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        var message = messages[index];
                        String senderName =
                            _usernamesCache[message.sender] ?? 'Unknown';
                        return MessageBubble(
                          sender: senderName,
                          text: message.text,
                          timestamp: message.timestamp,
                          isMe: message.isMe,
                          isRead: message.isRead,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Enter your message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15.0),
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    if (_messageController.text.isNotEmpty) {
                      _chatService.sendMessage(
                        widget.chatId,
                        _messageController.text,
                        user!.uid,
                      );
                      _messageController.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
