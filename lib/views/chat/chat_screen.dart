import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/models/message_model.dart';
import 'package:flutter_chat_app/widgets/message_bubble.dart';
import 'package:flutter_chat_app/views/user_profile_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_chat_app/views/profile/profile_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final User? user = FirebaseAuth.instance.currentUser;
  final ScrollController _scrollController = ScrollController();

  String? _chatPersonName;
  String? _chatPersonAvatarUrl;
  bool _chatPersonIsOnline = false;
  Map<String, String> _usernamesCache = {};
  bool _isTyping = false;
  bool _isSending = false;
  String _replyingTo = '';

  // For animations
  late AnimationController _sendButtonAnimationController;
  late Animation<double> _sendButtonAnimation;

  // Group messages by date
  Map<String, List<Message>> _groupedMessages = {};

  @override
  void initState() {
    super.initState();
    _loadChatPersonDetails();
    _cacheUsernames();
    _markMessagesAsRead();

    // Initialize animation controller for send button
    _sendButtonAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _sendButtonAnimation = CurvedAnimation(
      parent: _sendButtonAnimationController,
      curve: Curves.easeInOut,
    );

    // Listen to text changes to animate send button
    _messageController.addListener(_onMessageTextChanged);
  }

  void _onMessageTextChanged() {
    final hasText = _messageController.text.isNotEmpty;
    if (hasText && !_sendButtonAnimationController.isCompleted) {
      _sendButtonAnimationController.forward();
    } else if (!hasText && !_sendButtonAnimationController.isDismissed) {
      _sendButtonAnimationController.reverse();
    }

    // Update typing indicator in Firestore
    if (user != null) {
      _chatService.setTypingStatus(widget.chatId, user!.uid, hasText);
    }
  }

  @override
  void dispose() {
    // Clear typing status on dispose
    if (user != null) {
      _chatService.setTypingStatus(widget.chatId, user!.uid, false);
    }
    _messageController.dispose();
    _scrollController.dispose();
    _sendButtonAnimationController.dispose();
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

            // Start listening to typing status
            _listenToTypingStatus(chatPersonId);
          }
        }
      }
    }
  }

  void _listenToTypingStatus(String chatPersonId) {
    if (user == null) return;

    _chatService
        .getTypingStatus(widget.chatId, chatPersonId, user!.uid)
        .listen((isTyping) {
      if (mounted && isTyping != _isTyping) {
        setState(() {
          _isTyping = isTyping;
        });
      }
    });
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

  void _groupMessagesByDate(List<Message> messages) {
    _groupedMessages.clear();

    for (var message in messages) {
      final DateTime date = DateTime(
        message.timestamp.year,
        message.timestamp.month,
        message.timestamp.day,
      );

      final String dateKey = DateFormat('yyyy-MM-dd').format(date);

      if (!_groupedMessages.containsKey(dateKey)) {
        _groupedMessages[dateKey] = [];
      }

      _groupedMessages[dateKey]!.add(message);
    }
  }

  String _getDateDisplay(String dateKey) {
    final DateTime date = DateFormat('yyyy-MM-dd').parse(dateKey);
    final DateTime now = DateTime.now();
    final DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    } else if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    } else if (now.difference(date).inDays < 7) {
      return DateFormat('EEEE').format(date); // Day name
    } else {
      return DateFormat('MMMM d, yyyy').format(date); // Full date
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _replyToMessage(Message message) {
    setState(() {
      _replyingTo = message.text;
    });
    _messageController.text = '';
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(
                context, true); // ✅ Pass `true` to notify ChatListScreen
          },
        ),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _showChatPersonDetails,
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: _chatPersonAvatarUrl != null
                        ? NetworkImage(_chatPersonAvatarUrl!)
                        : null,
                    backgroundColor: colorScheme.primary.withOpacity(0.2),
                    child: _chatPersonAvatarUrl == null
                        ? Icon(Icons.person, color: colorScheme.primary)
                        : null,
                  ),
                  if (_chatPersonIsOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _chatPersonName ?? 'Loading...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      child: _isTyping
                          ? const Text(
                              'Typing...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            )
                          : Text(
                              _chatPersonIsOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                color: _chatPersonIsOnline
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Voice Call',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Voice calling coming soon!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Video Call',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Video calling coming soon!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'viewContact':
                  _showChatPersonDetails();
                  break;
                case 'search':
                  // Show search UI
                  break;
                case 'media':
                  // Show shared media
                  break;
                case 'block':
                  // Block user
                  break;
                case 'clear':
                  // Clear chat
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'viewContact',
                child: ListTile(
                  leading: Icon(Icons.person),
                  title: Text('View Contact'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'search',
                child: ListTile(
                  leading: Icon(Icons.search),
                  title: Text('Search'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'media',
                child: ListTile(
                  leading: Icon(Icons.photo_library),
                  title: Text('Media, links, and docs'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'block',
                child: ListTile(
                  leading: Icon(Icons.block, color: Colors.red),
                  title: Text('Block', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title:
                      Text('Clear chat', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: <Widget>[
              // Reply preview if user is replying to a message
              if (_replyingTo.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8.0),
                  color: colorScheme.surface,
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 40,
                        color: colorScheme.primary,
                        margin: const EdgeInsets.only(right: 8.0),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Reply to message',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _replyingTo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _cancelReply,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

              // Chat messages area
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withOpacity(0.5),
                    image: kIsWeb
                        ? null // No background image on web for better performance
                        : DecorationImage(
                            image: AssetImage(theme.brightness ==
                                    Brightness.dark
                                ? 'assets/images/chat_bg_dark.png' // Need to create these assets
                                : 'assets/images/chat_bg_light.png'),
                            opacity: 0.1,
                            repeat: ImageRepeat.repeat,
                          ),
                  ),
                  child: FutureBuilder<void>(
                    future: _cacheUsernames(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return StreamBuilder<List<Message>>(
                        stream:
                            _chatService.getMessages(widget.chatId, user!.uid),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Loading messages...',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            );
                          }

                          var messages = snapshot.data!;

                          // Group messages by date
                          _groupMessagesByDate(messages);

                          if (messages.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No messages yet',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Say hi to start the conversation!',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            controller: _scrollController,
                            reverse: true, // Reverse the order of the messages
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 8),
                            itemCount: _groupedMessages.length,
                            itemBuilder: (context, index) {
                              final dateKey =
                                  _groupedMessages.keys.elementAt(index);
                              final messagesForDate =
                                  _groupedMessages[dateKey]!;

                              return Column(
                                children: [
                                  // Date header
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surfaceVariant
                                              .withOpacity(0.7),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Text(
                                          _getDateDisplay(dateKey),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Messages for this date
                                  ...messagesForDate.map((message) {
                                    String senderName =
                                        _usernamesCache[message.sender] ??
                                            'Unknown';
                                    bool isFirstInGroup = true;
                                    bool isLastInGroup = true;

                                    // Find position in consecutive messages from same sender
                                    final senderMessages = messagesForDate
                                        .where(
                                            (m) => m.sender == message.sender)
                                        .toList();
                                    final messageIdx =
                                        senderMessages.indexOf(message);

                                    if (messageIdx > 0) {
                                      // Check if previous message is less than 2 minutes apart
                                      final prevMessage =
                                          senderMessages[messageIdx - 1];
                                      final timeDiff = message.timestamp
                                          .difference(prevMessage.timestamp)
                                          .inMinutes;

                                      isFirstInGroup = timeDiff > 2;
                                    }

                                    if (messageIdx <
                                        senderMessages.length - 1) {
                                      // Check if next message is less than 2 minutes apart
                                      final nextMessage =
                                          senderMessages[messageIdx + 1];
                                      final timeDiff = nextMessage.timestamp
                                          .difference(message.timestamp)
                                          .inMinutes;

                                      isLastInGroup = timeDiff > 2;
                                    }

                                    return GestureDetector(
                                      onLongPress: () {
                                        // Show message options
                                        HapticFeedback.mediumImpact();
                                        _showMessageOptions(message);
                                      },
                                      child: MessageBubble(
                                        sender: senderName,
                                        text: message.text,
                                        timestamp: message.timestamp,
                                        isMe: message.isMe,
                                        isRead: message.isRead,
                                        isFirstInGroup: isFirstInGroup,
                                        isLastInGroup: isLastInGroup,
                                      ),
                                    );
                                  }).toList(),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // Message input field
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      offset: const Offset(0, -1),
                      blurRadius: 5,
                      color: Colors.black.withOpacity(0.1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _showAttachmentOptions,
                      tooltip: 'Attach',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24.0),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: colorScheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _sendButtonAnimation,
                      builder: (context, child) {
                        return ScaleTransition(
                          scale: _sendButtonAnimation,
                          child: Container(
                            margin: const EdgeInsets.only(left: 4.0),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: _isSending
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send, color: Colors.white),
                              onPressed: _isSending ? null : _sendMessage,
                              tooltip: 'Send',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Bottom left floating buttons with tooltips - keep the existing code
          Positioned(
            left: 16,
            bottom: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Profile button
                Tooltip(
                  message: 'Profile',
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileScreen(),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.person,
                            color: colorScheme.primary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Settings button
                Tooltip(
                  message: 'Settings',
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SettingsScreen(),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.settings,
                            color: colorScheme.primary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Logout button
                Tooltip(
                  message: 'Logout',
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () async {
                          bool confirm = await showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Sign Out'),
                                  content: const Text(
                                      'Are you sure you want to sign out?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      child: const Text('Sign Out'),
                                    ),
                                  ],
                                ),
                              ) ??
                              false;

                          if (confirm && mounted) {
                            try {
                              await FirebaseAuth.instance.signOut();
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                    builder: (context) => LoginScreen()),
                                (route) => false,
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error signing out: $e')),
                              );
                            }
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.logout,
                            color: Colors.red,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _replyToMessage(message);
              },
            ),
            if (message.isMe) ...[
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  // Edit message functionality
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title:
                    const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  // Delete message functionality
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.text));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Message copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(context);
                // Forward message functionality
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions() {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Share Content',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAttachmentOption(
                    icon: Icons.photo,
                    label: 'Photos',
                    color: Colors.purple,
                    onTap: () {
                      Navigator.pop(context);
                      // Handle photo selection
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Photo sharing coming soon!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    color: Colors.red,
                    onTap: () {
                      Navigator.pop(context);
                      // Handle camera
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Camera sharing coming soon!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.insert_drive_file,
                    label: 'Document',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      // Handle document selection
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Document sharing coming soon!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.location_on,
                    label: 'Location',
                    color: Colors.green,
                    onTap: () {
                      Navigator.pop(context);
                      // Handle location sharing
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Location sharing coming soon!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty || _isSending) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    // Reset reply state
    setState(() {
      _isSending = true;
      _replyingTo = '';
    });

    try {
      await _chatService.sendMessage(
        widget.chatId,
        messageText,
        user!.uid,
      );

      // Scroll to bottom to show the new message
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
      print('Error sending message: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }
}
