import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/models/message_model.dart';
import 'package:flutter_chat_app/widgets/message_bubble.dart';

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
  String? _chatPersonEmail;
  String? _chatPersonAvatarUrl;
  Map<String, String> _usernamesCache = {};
  BuildContext? _ancestorContext;

  @override
  void initState() {
    super.initState();
    _loadChatPersonDetails();
    _cacheUsernames();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ancestorContext = context;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadChatPersonDetails() async {
    if (user != null) {
      DocumentSnapshot chatDoc = await _chatService.firestore.collection('chats').doc(widget.chatId).get();
      if (chatDoc.exists) {
        List<dynamic> userIds = chatDoc['userIds'];
        String? chatPersonId = userIds.firstWhere((id) => id != user!.uid, orElse: () => null);
        if (chatPersonId != null) {
          DocumentSnapshot userDoc = await _chatService.firestore.collection('users').doc(chatPersonId).get();
          if (userDoc.exists && mounted) {
            final userData = userDoc.data() as Map<String, dynamic>?;
            setState(() {
              _chatPersonName = userData?['username'];
              _chatPersonEmail = userData?['email'];
              _chatPersonAvatarUrl = userData != null && userData.containsKey('avatarUrl') ? userData['avatarUrl'] : null;
            });
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
      DocumentSnapshot chatDoc = await _chatService.firestore.collection('chats').doc(widget.chatId).get();
      if (chatDoc.exists) {
        List<dynamic> userIds = chatDoc['userIds'];
        for (String userId in userIds) {
          if (userId != user!.uid) {
            String? username = await _chatService.getUsername(userId);
            if (username != null) {
              _usernamesCache[userId] = username;
            }
          }
        }
      }
    }
  }

  void _showChatPersonDetails() {
    if (!mounted) return; // Ensure the widget is still mounted
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Chat Person Details'),
          content: _chatPersonName != null && _chatPersonEmail != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_chatPersonAvatarUrl != null)
                      CircleAvatar(
                        backgroundImage: NetworkImage(_chatPersonAvatarUrl!),
                        radius: 40,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      'Name: $_chatPersonName',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text('Email: $_chatPersonEmail'),
                  ],
                )
              : const CircularProgressIndicator(),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context, true); // ✅ Pass `true` to notify ChatListScreen
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showChatPersonDetails,
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _cacheUsernames(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: <Widget>[
              Expanded(
                child: StreamBuilder<List<Message>>(
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
                        String senderName = _usernamesCache[message.sender] ?? 'Unknown';
                        return MessageBubble(
                          sender: senderName,
                          text: message.text,
                          timestamp: message.timestamp,
                          isMe: message.isMe,
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
                            user!.uid,
                            _messageController.text,
                          );
                          _messageController.clear();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}