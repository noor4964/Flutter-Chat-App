import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/image_picker_helper.dart';
import 'package:flutter_chat_app/services/storage_service.dart';
import 'package:image_picker/image_picker.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String chatName;

  const ChatDetailScreen({
    Key? key,
    required this.chatId,
    required this.chatName,
  }) : super(key: key);

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final StorageService _storageService = StorageService();
  final currentUser = FirebaseAuth.instance.currentUser;
  bool _isAttaching = false;
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      await _chatService.sendMessage(
        widget.chatId,
        _messageController.text,
        currentUser!.uid,
      );
      _messageController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _sendImageMessage() async {
    try {
      setState(() {
        _isAttaching = true;
      });

      final XFile? image = await ImagePickerHelper.pickImage(isCamera: false);

      if (image == null) {
        setState(() {
          _isAttaching = false;
        });
        return;
      }

      // Upload image to Firebase Storage
      final imageUrl = await _storageService.uploadImage(
        image,
        'chat_images/${widget.chatId}',
      );

      if (imageUrl != null) {
        // Send image URL as message
        await _chatService.sendImageMessage(
          widget.chatId,
          imageUrl,
          currentUser!.uid,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending image: $e')),
      );
    } finally {
      setState(() {
        _isAttaching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatName),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Show chat info dialog
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Chat with ${widget.chatName}'),
                  content: const Text('Chat information will appear here'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No messages yet'));
                }

                // Mark messages as read
                _chatService.markChatAsRead(widget.chatId, currentUser!.uid);

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  padding:
                      EdgeInsets.all(PlatformHelper.isDesktop ? 16.0 : 8.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        messages[index].data() as Map<String, dynamic>;
                    final isCurrentUser =
                        message['senderId'] == currentUser!.uid;
                    final messageType = message['type'] ?? 'text';

                    return Align(
                      alignment: isCurrentUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 8.0,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrentUser
                              ? Colors.deepPurple
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                        ),
                        child: messageType == 'image'
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: Image.network(
                                  message['content'],
                                  loadingBuilder: (BuildContext context,
                                      Widget child,
                                      ImageChunkEvent? loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      width: 200,
                                      height: 200,
                                      alignment: Alignment.center,
                                      child: CircularProgressIndicator(
                                        value: loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message['content'],
                                    style: TextStyle(
                                      color: isCurrentUser
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 4.0),
                                  Text(
                                    _formatTimestamp(message['timestamp']),
                                    style: TextStyle(
                                      color: isCurrentUser
                                          ? Colors.white.withOpacity(0.7)
                                          : Colors.black54,
                                      fontSize: 10.0,
                                    ),
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

          // Message input
          Container(
            padding: EdgeInsets.all(PlatformHelper.isDesktop ? 16.0 : 8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _isAttaching ? null : _sendImageMessage,
                ),
                if (PlatformHelper.isCameraAvailable())
                  IconButton(
                    icon: const Icon(Icons.camera_alt),
                    onPressed: _isAttaching
                        ? null
                        : () async {
                            try {
                              setState(() {
                                _isAttaching = true;
                              });

                              final XFile? image =
                                  await ImagePickerHelper.pickImage(
                                isCamera: true,
                              );

                              if (image == null) {
                                setState(() {
                                  _isAttaching = false;
                                });
                                return;
                              }

                              // Upload image to Firebase Storage
                              final imageUrl =
                                  await _storageService.uploadImage(
                                image,
                                'chat_images/${widget.chatId}',
                              );

                              if (imageUrl != null) {
                                // Send image URL as message
                                await _chatService.sendImageMessage(
                                  widget.chatId,
                                  imageUrl,
                                  currentUser!.uid,
                                );
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error sending image: $e')),
                              );
                            } finally {
                              setState(() {
                                _isAttaching = false;
                              });
                            }
                          },
                  ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _isSending ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      // Today, show time
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      // Not today, show date
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
