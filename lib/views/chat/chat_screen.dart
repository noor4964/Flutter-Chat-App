import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/models/message_model.dart';

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

  @override
  void initState() {
    super.initState();
    _loadChatPersonDetails();
  }

  Future<void> _loadChatPersonDetails() async {
    if (user != null) {
      DocumentSnapshot chatDoc = await _chatService.firestore.collection('chats').doc(widget.chatId).get();
      List<dynamic> userIds = chatDoc['userIds'];
      String chatPersonId = userIds.firstWhere((id) => id != user!.uid);
      _chatPersonName = await _chatService.getUsername(chatPersonId);
      DocumentSnapshot userDoc = await _chatService.firestore.collection('users').doc(chatPersonId).get();
      setState(() {
        _chatPersonEmail = userDoc['email'];
      });
    }
  }

  void _showChatPersonDetails() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Chat Person Details'),
          content: _chatPersonName != null && _chatPersonEmail != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Name: $_chatPersonName'),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showChatPersonDetails,
          ),
        ],
      ),
      body: Column(
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
                    bool isMe = message.isMe;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 10.0),
                        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15.0),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blueAccent : Colors.grey[300],
                          borderRadius: BorderRadius.circular(15.0),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: <Widget>[
                            FutureBuilder<String?>(
                              future: _chatService.getUsername(message.sender),
                              builder: (context, usernameSnapshot) {
                                if (!usernameSnapshot.hasData) {
                                  return Text(
                                    'Loading...',
                                    style: TextStyle(color: isMe ? Colors.white : Colors.black),
                                  );
                                }
                                return Text(
                                  usernameSnapshot.data ?? 'Unknown',
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 5.0),
                            Text(
                              message.text,
                              style: TextStyle(color: isMe ? Colors.white : Colors.black),
                            ),
                          ],
                        ),
                      ),
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
      ),
    );
  }
}