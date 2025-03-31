import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/image_picker_helper.dart';
import 'package:flutter_chat_app/services/storage_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:transparent_image/transparent_image.dart';

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

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final StorageService _storageService = StorageService();
  final currentUser = FirebaseAuth.instance.currentUser;
  bool _isAttaching = false;

  // Keep track of pending messages for optimistic UI
  final List<Map<String, dynamic>> _pendingMessages = [];
  final _uuid = Uuid();

  // Improved message handling for seamless experience
  List<Map<String, dynamic>> _allMessages = [];
  bool _initialLoadDone = false;
  bool _isFirstLoad = true;
  bool _hasMoreMessages = true;
  final int _messageBatchSize = 30;

  // Local caching for seamless experience
  bool _isLoadingFromCache = false;
  String get _cacheKey => 'chat_messages_${widget.chatId}';

  // Typing indicator variables
  bool _isOtherUserTyping = false;
  Timer? _typingTimer;
  Timer? _otherUserTypingTimer;

  // Scroll controller with position maintenance
  ScrollController _scrollController = ScrollController();

  // Stream subscription for message updates
  StreamSubscription<QuerySnapshot>? _messageSubscription;
  StreamSubscription<DocumentSnapshot>? _typingSubscription;

  @override
  bool get wantKeepAlive => true; // Keep state alive when navigating

  @override
  void initState() {
    super.initState();
    // Load cached messages first for immediate display
    _loadCachedMessages();

    // Set up typing indicator listener
    _setupTypingListener();

    // Set up scroll listener for pagination
    _scrollController.addListener(_scrollListener);

    // Setup typing notification
    _messageController.addListener(_onTypingChanged);
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        _hasMoreMessages &&
        !_isLoadingMoreMessages) {
      _loadMoreMessages();
    }
  }

  bool _isLoadingMoreMessages = false;
  // Add flag to control loading visibility
  bool _shouldShowLoading = false;

  Future<void> _loadMoreMessages() async {
    if (!_hasMoreMessages || _isLoadingMoreMessages) return;

    setState(() {
      _isLoadingMoreMessages = true;
      // Only show loading after a short delay to prevent flicker
      Future.delayed(Duration(milliseconds: 300), () {
        if (_isLoadingMoreMessages && mounted) {
          setState(() {
            _shouldShowLoading = true;
          });
        }
      });
    });

    try {
      final lastMessage = _allMessages.isNotEmpty ? _allMessages.last : null;
      if (lastMessage == null) {
        setState(() {
          _isLoadingMoreMessages = false;
        });
        return;
      }

      final lastTimestamp = lastMessage['timestamp'] as Timestamp?;
      if (lastTimestamp == null) {
        setState(() {
          _isLoadingMoreMessages = false;
          _hasMoreMessages = false;
        });
        return;
      }

      final moreMessages = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .startAfter([lastTimestamp])
          .limit(_messageBatchSize)
          .get();

      if (moreMessages.docs.isEmpty) {
        setState(() {
          _hasMoreMessages = false;
          _isLoadingMoreMessages = false;
        });
        return;
      }

      final newMessages = moreMessages.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();

      setState(() {
        _allMessages.addAll(newMessages);
        _isLoadingMoreMessages = false;
      });
    } catch (e) {
      print('Error loading more messages: $e');
      setState(() {
        _isLoadingMoreMessages = false;
        _shouldShowLoading = false;
      });
    }
  }

  // Load messages from local cache for instant display
  Future<void> _loadCachedMessages() async {
    setState(() {
      _isLoadingFromCache = true;
    });

    try {
      // Load messages from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final cachedMessagesJson = prefs.getString(_cacheKey);

      if (cachedMessagesJson != null) {
        // Parse cached messages and display them immediately
        final List<dynamic> decoded = jsonDecode(cachedMessagesJson);
        final List<Map<String, dynamic>> cachedMessages =
            decoded.map((item) => _convertTimestamps(item)).toList();

        if (cachedMessages.isNotEmpty && mounted) {
          setState(() {
            _allMessages = cachedMessages;
            _initialLoadDone = true;
            _isLoadingFromCache = false;
          });

          // Fetch fresh messages from server in the background
          _fetchMessagesFromServer();
        } else {
          _fetchMessagesFromServer();
        }
      } else {
        // No cache - load from server
        _fetchMessagesFromServer();
      }
    } catch (e) {
      print('Error loading cached messages: $e');
      // Fall back to server fetch
      _fetchMessagesFromServer();
    }
  }

  // Helper to convert timestamp strings back to Firestore Timestamps
  Map<String, dynamic> _convertTimestamps(dynamic item) {
    final Map<String, dynamic> message = Map<String, dynamic>.from(item);

    // Convert timestamp from stored format back to Firestore Timestamp
    if (message.containsKey('timestamp') && message['timestamp'] is Map) {
      final timestampData = message['timestamp'] as Map;
      if (timestampData.containsKey('seconds') &&
          timestampData.containsKey('nanoseconds')) {
        message['timestamp'] =
            Timestamp(timestampData['seconds'], timestampData['nanoseconds']);
      }
    }

    return message;
  }

  // Cache messages locally for faster loading next time
  Future<void> _saveMessagesToCache() async {
    try {
      // Don't cache if we have no messages
      if (_allMessages.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();

      // Convert Timestamp objects to a serializable format
      final List<Map<String, dynamic>> messagesToCache =
          _allMessages.take(50).map((msg) {
        final Map<String, dynamic> copy = Map<String, dynamic>.from(msg);

        // Make timestamp serializable
        if (copy['timestamp'] is Timestamp) {
          final Timestamp ts = copy['timestamp'];
          copy['timestamp'] = {
            'seconds': ts.seconds,
            'nanoseconds': ts.nanoseconds
          };
        }

        return copy;
      }).toList();

      // Save to SharedPreferences
      await prefs.setString(_cacheKey, jsonEncode(messagesToCache));
    } catch (e) {
      print('Error saving messages to cache: $e');
      // Non-critical error, can be ignored
    }
  }

  void _setupMessageListener() {
    // Cancel existing subscription if any
    _messageSubscription?.cancel();

    // Listen only for new messages (more efficient than reloading everything)
    _messageSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1) // Only get newest message
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) return;

      // Only process if we have a document
      final newMessageData = snapshot.docs.first.data();
      final newMessageId = newMessageData['id'];

      // If we already have this message, don't add it again
      if (_allMessages.isNotEmpty && _allMessages.first['id'] == newMessageId) {
        return;
      }

      // Check if this is a message we just sent (from pending)
      final pendingIndex = _pendingMessages.indexWhere((msg) =>
          msg['content'] == newMessageData['content'] &&
          msg['senderId'] == newMessageData['senderId']);

      if (pendingIndex != -1) {
        // Remove from pending as it's now confirmed
        setState(() {
          _pendingMessages.removeAt(pendingIndex);
        });
      }

      // Add new message at the beginning (most recent)
      setState(() {
        _allMessages.insert(0, newMessageData);
      });

      // Mark new message as read if from other user
      if (newMessageData['senderId'] != currentUser!.uid) {
        _chatService.markChatAsRead(widget.chatId, currentUser!.uid);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    super.dispose();
  }

  // Optimistically update UI with new message immediately
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    // Create a temporary message ID
    final String tempId = _uuid.v4();
    final timestamp = Timestamp.now();

    // Create a new message object with a temporary pending state
    final pendingMessage = {
      'id': tempId,
      'content': messageText,
      'senderId': currentUser!.uid,
      'timestamp': timestamp,
      'readBy': [currentUser!.uid],
      'type': 'text',
      'isPending': true,
    };

    // Add to pending messages list and update UI immediately
    setState(() {
      _pendingMessages.add(pendingMessage);

      // Also immediately add to the all messages for seamless UI
      _allMessages.insert(0, pendingMessage);
    });

    // Scroll to the newest message
    _scrollToBottom();

    try {
      // Send the message to Firebase in the background
      await _chatService.sendMessage(
        widget.chatId,
        messageText,
        currentUser!.uid,
      );

      // Once successfully sent, remove from pending list (the listener will handle confirmed message)
      if (mounted) {
        setState(() {
          // Remove this message from pending list only
          _pendingMessages.removeWhere((msg) => msg['id'] == tempId);

          // Don't need to modify _allMessages since the server message will replace it via listener
        });
      }
    } catch (e) {
      // Mark message as failed if there was an error
      if (mounted) {
        setState(() {
          // Update in both pending messages and all messages
          final pendingIndex =
              _pendingMessages.indexWhere((msg) => msg['id'] == tempId);
          if (pendingIndex != -1) {
            _pendingMessages[pendingIndex]['isFailed'] = true;
            _pendingMessages[pendingIndex]['isPending'] = false;
          }

          final allMessagesIndex =
              _allMessages.indexWhere((msg) => msg['id'] == tempId);
          if (allMessagesIndex != -1) {
            _allMessages[allMessagesIndex]['isFailed'] = true;
            _allMessages[allMessagesIndex]['isPending'] = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: $e'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                // Remove the failed message and retry
                setState(() {
                  _pendingMessages.removeWhere((msg) => msg['id'] == tempId);
                  _allMessages.removeWhere((msg) => msg['id'] == tempId);
                });
                _messageController.text = messageText;
              },
            ),
          ),
        );
      }
    }
  }

  // Smoothly scroll to bottom
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  // Enhanced image sending with optimistic UI
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

      // Create a temporary message for optimistic UI
      final String tempId = _uuid.v4();
      final timestamp = Timestamp.now();
      final pendingMessage = {
        'id': tempId,
        'content': 'Uploading image...',
        'senderId': currentUser!.uid,
        'timestamp': timestamp,
        'readBy': [currentUser!.uid],
        'type': 'text', // Temporary text type while uploading
        'isPending': true,
        'isUploading': true,
      };

      // Show uploading placeholder
      setState(() {
        _pendingMessages.add(pendingMessage);
        _allMessages.insert(0, pendingMessage);
        _isAttaching = false; // We'll handle loading state in the message UI
      });

      // Scroll to show uploading message
      _scrollToBottom();

      // Upload image to Firebase Storage
      final imageUrl = await _storageService.uploadImage(
        image,
        'chat_images/${widget.chatId}',
      );

      if (imageUrl != null && mounted) {
        // Remove the uploading placeholder
        setState(() {
          _pendingMessages.removeWhere((msg) => msg['id'] == tempId);
          _allMessages.removeWhere((msg) => msg['id'] == tempId);
        });

        // Create a new temporary message with the image URL
        final imageMessage = {
          'id': '${tempId}_image',
          'content': imageUrl,
          'senderId': currentUser!.uid,
          'timestamp': timestamp,
          'readBy': [currentUser!.uid],
          'type': 'image',
          'isPending': true,
        };

        // Show image immediately
        setState(() {
          _pendingMessages.add(imageMessage);
          _allMessages.insert(0, imageMessage);
        });

        // Send image URL as message
        await _chatService.sendImageMessage(
          widget.chatId,
          imageUrl,
          currentUser!.uid,
        );

        // Remove from pending when confirmed
        if (mounted) {
          setState(() {
            _pendingMessages
                .removeWhere((msg) => msg['id'] == '${tempId}_image');
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAttaching = false;
        });
      }
    }
  }

  void _setupTypingListener() {
    // Cancel existing subscription if any
    _typingSubscription?.cancel();

    // Listen for typing status of other user(s)
    _typingSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        // Get the typing status for the other user
        final typingData = snapshot.data()?['typing'] as Map<String, dynamic>?;

        if (typingData != null) {
          // Check if any user other than current user is typing
          bool someoneIsTyping = false;
          typingData.forEach((userId, isTyping) {
            if (userId != currentUser!.uid && isTyping == true) {
              someoneIsTyping = true;
            }
          });

          if (mounted && _isOtherUserTyping != someoneIsTyping) {
            setState(() {
              _isOtherUserTyping = someoneIsTyping;
            });

            // Reset the typing timer if needed
            if (someoneIsTyping) {
              _resetOtherUserTypingTimer();
            }
          }
        }
      }
    });
  }

  void _resetOtherUserTypingTimer() {
    // Cancel existing timer if any
    _otherUserTypingTimer?.cancel();

    // Set a timer to automatically reset typing status after 5 seconds
    // This handles cases where the typing indicator gets stuck
    _otherUserTypingTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isOtherUserTyping) {
        setState(() {
          _isOtherUserTyping = false;
        });
      }
    });
  }

  // Preload image to prevent flickering when displaying
  Future<void> _preloadImage(String imageUrl) async {
    await precacheImage(NetworkImage(imageUrl), context);
  }

  void _onTypingChanged() {
    final isTyping = _messageController.text.isNotEmpty;

    // Reset any existing typing timer
    _typingTimer?.cancel();

    // Update typing status in Firestore
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'typing.${currentUser!.uid}': isTyping,
    }).catchError((error) {
      // If the typing field doesn't exist yet, create it
      FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set({
        'typing': {currentUser!.uid: isTyping},
      }, SetOptions(merge: true));
    });

    // Set a timer to reset typing status after user stops typing
    if (isTyping) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .update({
          'typing.${currentUser!.uid}': false,
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

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
          // Typing indicator (shows when other user is typing)
          if (_isOtherUserTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: List.generate(3, (index) {
                        return Positioned(
                          left: index * 4.0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0, end: 1),
                                duration:
                                    Duration(milliseconds: 500 + (index * 200)),
                                builder: (context, value, child) {
                                  return Transform.scale(
                                    scale: 0.5 + (value * 0.5),
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade400,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.chatName} is typing...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          // Chat messages
          Expanded(
            child: _allMessages.isNotEmpty || _pendingMessages.isNotEmpty
                ? _buildMessageList([..._pendingMessages, ..._allMessages])
                : (_isLoadingFromCache && _isFirstLoad)
                    ? Center(
                        child: CircularProgressIndicator(),
                      )
                    : Container(), // Empty container instead of loading indicator
          ),

          // Loading indicator for pagination at bottom (only shown after delay)
          if (_shouldShowLoading && _isLoadingMoreMessages)
            Container(
              height: 30,
              alignment: Alignment.center,
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
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

                              // Create a temporary message for optimistic UI
                              final String tempId = _uuid.v4();
                              final timestamp = Timestamp.now();
                              final pendingMessage = {
                                'id': tempId,
                                'content': 'Uploading image...',
                                'senderId': currentUser!.uid,
                                'timestamp': timestamp,
                                'readBy': [currentUser!.uid],
                                'type': 'text',
                                'isPending': true,
                                'isUploading': true,
                              };

                              // Show uploading placeholder
                              setState(() {
                                _pendingMessages.add(pendingMessage);
                                _allMessages.insert(0, pendingMessage);
                                _isAttaching = false;
                              });

                              // Scroll to show uploading message
                              _scrollToBottom();

                              // Upload image to Firebase Storage
                              final imageUrl =
                                  await _storageService.uploadImage(
                                image,
                                'chat_images/${widget.chatId}',
                              );

                              if (imageUrl != null && mounted) {
                                // Remove the uploading placeholder
                                setState(() {
                                  _pendingMessages.removeWhere(
                                      (msg) => msg['id'] == tempId);
                                  _allMessages.removeWhere(
                                      (msg) => msg['id'] == tempId);
                                });

                                // Create image message with optimistic UI
                                final imageMessage = {
                                  'id': '${tempId}_image',
                                  'content': imageUrl,
                                  'senderId': currentUser!.uid,
                                  'timestamp': timestamp,
                                  'readBy': [currentUser!.uid],
                                  'type': 'image',
                                  'isPending': true,
                                };

                                // Show image immediately
                                setState(() {
                                  _pendingMessages.add(imageMessage);
                                  _allMessages.insert(0, imageMessage);
                                });

                                // Send image URL as message
                                await _chatService.sendImageMessage(
                                  widget.chatId,
                                  imageUrl,
                                  currentUser!.uid,
                                );

                                // Remove from pending when confirmed
                                if (mounted) {
                                  setState(() {
                                    _pendingMessages.removeWhere((msg) =>
                                        msg['id'] == '${tempId}_image');
                                  });
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Error sending image: $e')),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isAttaching = false;
                                });
                              }
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
                  icon: const Icon(Icons.send),
                  onPressed: _messageController.text.trim().isEmpty
                      ? null
                      : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Method to build the chat message list
  Widget _buildMessageList(List<Map<String, dynamic>> messages) {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(10),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isCurrentUser = message['senderId'] == currentUser!.uid;
        final isImage = message['type'] == 'image';
        final isPending = message['isPending'] == true;
        final isFailed = message['isFailed'] == true;
        final isUploading = message['isUploading'] == true;

        // Preload images when they appear in the list for smoother experience
        if (isImage && !isUploading && message['content'] is String) {
          _preloadImage(message['content']);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment:
                isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: isImage
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isCurrentUser
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.8)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Message content
                  if (isImage && !isUploading)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: GestureDetector(
                        onTap: () {
                          // Show full-screen image view
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              insetPadding: EdgeInsets.zero,
                              child: Stack(
                                children: [
                                  InteractiveViewer(
                                    child: Image.network(
                                      message['content'],
                                      fit: BoxFit.contain,
                                      // Use FadeInImage for smoother image loading
                                      loadingBuilder: (_, __, ___) =>
                                          FadeInImage(
                                        placeholder:
                                            MemoryImage(kTransparentImage),
                                        image: NetworkImage(message['content']),
                                        fit: BoxFit.contain,
                                        fadeInDuration:
                                            const Duration(milliseconds: 300),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.white),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        // Use FadeInImage for smoother image loading
                        child: FadeInImage(
                          placeholder: MemoryImage(kTransparentImage),
                          image: NetworkImage(message['content']),
                          fit: BoxFit.cover,
                          width: 200,
                          fadeInDuration: const Duration(milliseconds: 300),
                          imageErrorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 200,
                              height: 150,
                              color: Colors.grey[300],
                              child: Center(
                                child: Icon(Icons.broken_image, size: 40),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  else if (isUploading)
                    SizedBox(
                      width: 150,
                      height: 100,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 8),
                            Text(
                              'Uploading image...',
                              style: TextStyle(
                                color: isCurrentUser
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      message['content'],
                      style: TextStyle(
                        color: isCurrentUser ? Colors.white : Colors.black,
                        fontSize: 16,
                      ),
                    ),

                  const SizedBox(height: 4),

                  // Message status indicators
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPending && !isFailed && !isUploading)
                        const Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey,
                        )
                      else if (isFailed)
                        const Icon(
                          Icons.error_outline,
                          size: 12,
                          color: Colors.red,
                        )
                      else if (isCurrentUser)
                        Icon(
                          Icons.check_circle,
                          size: 12,
                          color: (message['readBy'] ?? []).length > 1
                              ? Colors.green
                              : Colors.grey,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        message['timestamp'] is Timestamp
                            ? _formatTimestamp(message['timestamp'])
                            : '',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

  // Fetch fresh messages from server
  Future<void> _fetchMessagesFromServer() async {
    try {
      final messagesQuery = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(_messageBatchSize)
          .get();

      if (messagesQuery.docs.isNotEmpty) {
        final loadedMessages = messagesQuery.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .toList();

        // Mark messages as read
        _chatService.markChatAsRead(widget.chatId, currentUser!.uid);

        if (mounted) {
          setState(() {
            _allMessages = loadedMessages;
            _initialLoadDone = true;
            _hasMoreMessages = messagesQuery.docs.length >= _messageBatchSize;
            _isFirstLoad = false;
          });

          // Cache messages locally for faster loading next time
          _saveMessagesToCache();

          // Set up real-time listener for new messages after initial load
          _setupMessageListener();
        }
      } else {
        if (mounted) {
          setState(() {
            _initialLoadDone = true;
            _hasMoreMessages = false;
            _isFirstLoad = false;
          });

          // Still set up listener for first message
          _setupMessageListener();
        }
      }
    } catch (e) {
      print('Error fetching messages from server: $e');
      if (mounted) {
        setState(() {
          _initialLoadDone = true;
          _isFirstLoad = false;
        });
      }
    }
  }
}
