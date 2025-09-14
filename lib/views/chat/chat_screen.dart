import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/services/chat_notification_service.dart';
import 'package:flutter_chat_app/services/presence_service.dart';
import 'package:flutter_chat_app/models/message_model.dart';
import 'package:flutter_chat_app/widgets/modern_message_bubble.dart';
import 'package:flutter_chat_app/widgets/message_reaction_widgets.dart';
import 'package:flutter_chat_app/views/user_profile_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';
import 'package:flutter_chat_app/views/calls/audio_call_screen.dart';
import 'package:flutter_chat_app/views/calls/video_call_screen.dart';
import 'dart:async';
import '../../../utils/user_friendly_error_handler.dart';

enum MessageStatus {
  sending,
  sent,
  seen,
}

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
  bool _isEmojiPickerOpen = false; // State variable for emoji picker

  // Ajax-type system variables
  bool _isConnected = true; // Connection status for real-time feedback
  Timer? _connectionCheckTimer; // Periodic connection checking

  // For animations
  late AnimationController _sendButtonAnimationController;
  late Animation<double> _sendButtonAnimation;

  // Group messages by date
  Map<String, List<Message>> _groupedMessages = {};

  // Timer for periodically marking messages as read
  Timer? _messageReadTimer;

  // Keyboard state tracking for consistent scrolling
  double _lastKeyboardHeight = 0.0;
  bool _isKeyboardAnimating = false;

  @override
  void initState() {
    super.initState();
    _loadChatPersonDetails();
    _cacheUsernames();

    // Mark messages as read when the chat is opened
    _markMessagesAsRead();

    // Set up a timer to periodically mark messages as read
    _setupMessageReadTimer();

    // Update presence to show that user is in this chat
    _updatePresence(true);

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

    // Initialize Ajax-type connection monitoring
    _startConnectionMonitoring();

    // Add keyboard listener to handle consistent scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupKeyboardListener();
    });
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

    // Update presence to show that user is no longer in this chat
    _updatePresence(false);

    _messageController.dispose();
    _scrollController.dispose();
    _sendButtonAnimationController.dispose();

    // Cancel message read timer
    _messageReadTimer?.cancel();

    // Cancel connection monitoring timer
    _connectionCheckTimer?.cancel();

    super.dispose();
  }

  // Update user presence when entering or leaving a chat
  Future<void> _updatePresence(bool inChat) async {
    try {
      final presenceService = PresenceService();
      if (inChat) {
        await presenceService.setActiveChat(widget.chatId);

        // Also mark notifications as read for this chat
        final notificationService = ChatNotificationService();
        await notificationService.markChatNotificationsAsRead(widget.chatId);
      } else {
        await presenceService.clearActiveChat();
      }
    } catch (e) {
      print('❌ Error updating presence: $e');
    }
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

  void _setupMessageReadTimer() {
    // Cancel any existing timer
    _messageReadTimer?.cancel();

    // Create a new timer that periodically marks messages as read
    _messageReadTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (user != null && mounted) {
        // Mark messages as read
        await _chatService.markMessagesAsRead(widget.chatId, user!.uid);

        // Also mark the chat as read at the chat level
        await _chatService.markChatAsRead(widget.chatId, user!.uid);

        print('Automatically marked messages as read');
      }
    });
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

    // Sort messages within each date group in chronological order (oldest first)
    _groupedMessages.forEach((dateKey, messageList) {
      messageList.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
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

  // Update the _scrollToBottom method for more controlled scrolling
  void _scrollToBottom() {
    if (_scrollController.hasClients && mounted && !_isKeyboardAnimating) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
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
    final isTabletOrDesktop = MediaQuery.of(context).size.width > 600;
    
    // Track keyboard height changes for consistent scrolling
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    
    // Handle keyboard appearance/disappearance consistently
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (keyboardHeight != _lastKeyboardHeight && !_isKeyboardAnimating) {
        _handleKeyboardChange(keyboardHeight > _lastKeyboardHeight);
        _lastKeyboardHeight = keyboardHeight;
      }
    });

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 2.0,
        backgroundColor: theme.brightness == Brightness.dark
            ? colorScheme.surface
            : colorScheme.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: theme.brightness == Brightness.dark ? null : Colors.white,
          onPressed: () {
            Navigator.pop(context, true);
          },
        ),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _showChatPersonDetails,
          child: Row(
            children: [
              Hero(
                tag: 'profile-${widget.chatId}',
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: _chatPersonAvatarUrl != null
                          ? NetworkImage(_chatPersonAvatarUrl!)
                          : null,
                      backgroundColor: theme.brightness == Brightness.dark
                          ? colorScheme.primary.withOpacity(0.2)
                          : Colors.white.withOpacity(0.9),
                      child: _chatPersonAvatarUrl == null
                          ? Icon(Icons.person,
                              color: theme.brightness == Brightness.dark
                                  ? colorScheme.primary
                                  : colorScheme.primary)
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
                            border: Border.all(
                              color: theme.brightness == Brightness.dark
                                  ? colorScheme.surface
                                  : colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _chatPersonName ?? 'Loading...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        overflow: TextOverflow.ellipsis,
                        color: theme.brightness == Brightness.dark
                            ? null
                            : Colors.white,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      child: _isTyping
                          ? Text(
                              'Typing...',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.brightness == Brightness.dark
                                    ? Colors.green
                                    : Colors.white.withOpacity(0.9),
                              ),
                            )
                          : Text(
                              _chatPersonIsOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.brightness == Brightness.dark
                                    ? _chatPersonIsOnline
                                        ? Colors.green
                                        : Colors.grey
                                    : Colors.white.withOpacity(
                                        _chatPersonIsOnline ? 0.9 : 0.7),
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
          // Connection status indicator for Ajax-type system
          _buildConnectionIndicator(theme),
          IconButton(
            icon: const Icon(Icons.call),
            color: theme.brightness == Brightness.dark ? null : Colors.white,
            tooltip: 'Voice Call',
            onPressed: _startAudioCall,
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            color: theme.brightness == Brightness.dark ? null : Colors.white,
            tooltip: 'Video Call',
            onPressed: _startVideoCall,
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: theme.brightness == Brightness.dark ? null : Colors.white,
            ),
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
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? colorScheme.surfaceVariant
                        : colorScheme.primary.withOpacity(0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
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
                        icon: const Icon(Icons.close, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _cancelReply,
                      ),
                    ],
                  ),
                ),

              // Chat messages area - wrapped in flexible to prevent overflow
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withOpacity(0.5),
                    image: kIsWeb
                        ? null // No background image on web for better performance
                        : DecorationImage(
                            image: AssetImage(
                                theme.brightness == Brightness.dark
                                    ? 'assets/images/chat_bg_dark.png'
                                    : 'assets/images/chat_bg_light.png'),
                            opacity: 0.1,
                            repeat: ImageRepeat.repeat,
                          ),
                  ),
                  // This padding makes the chat content more centered on larger screens
                  padding: isTabletOrDesktop
                      ? EdgeInsets.symmetric(
                          horizontal: MediaQuery.of(context).size.width * 0.1)
                      : EdgeInsets.zero,
                  child: FutureBuilder<void>(
                    future: _cacheUsernames(),
                    builder: (context, snapshot) {
                      // No loading indicator, directly return StreamBuilder
                      return StreamBuilder<List<Message>>(
                        stream:
                            _chatService.getMessages(widget.chatId, user!.uid),
                        builder: (context, snapshot) {
                          // Only show empty state if we have data but it's empty
                          // or if there's an error
                          if (snapshot.hasError) {
                            return Center(
                              child: Text('Error: ${snapshot.error}'),
                            );
                          }

                          // If we have data, use it
                          if (snapshot.hasData) {
                            var messages = snapshot.data!;

                            // Group messages by date
                            _groupMessagesByDate(messages);

                            // Only show empty chat if we explicitly have empty data
                            if (messages.isEmpty) {
                              return _buildEmptyChat();
                            }

                            // Add pull-to-refresh for Ajax-type experience
                            return RefreshIndicator(
                              onRefresh: _refreshChatData,
                              child: ListView.builder(
                                controller: _scrollController,
                                reverse:
                                    true, // Reverse the order of the messages
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 8),
                                itemCount: _groupedMessages.length,
                                // Add physics to prevent over-scrolling during keyboard events
                                physics: const ClampingScrollPhysics(),
                                itemBuilder: (context, index) {
                                final dateKey =
                                    _groupedMessages.keys.elementAt(index);
                                final messagesForDate =
                                    _groupedMessages[dateKey]!;

                                // Calculate max width for bubbles depending on screen size
                                final screenWidth =
                                    MediaQuery.of(context).size.width;
                                final maxBubbleWidth = isTabletOrDesktop
                                    ? screenWidth * 0.6 // 60% on larger screens
                                    : screenWidth * 0.75; // 75% on mobile

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
                                            boxShadow: [
                                              BoxShadow(
                                                blurRadius: 4,
                                                color: Colors.black
                                                    .withOpacity(0.1),
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          child: Text(
                                            _getDateDisplay(dateKey),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Messages for this date - organized by sender
                                    ...messagesForDate.map((message) {
                                      bool isFirstInGroup = true;

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

                                      return Hero(
                                        tag:
                                            'message-${message.id}-${message.timestamp.millisecondsSinceEpoch}',
                                        child: Material(
                                          color: Colors.transparent,
                                          child: Row(
                                            mainAxisAlignment: message.isMe
                                                ? MainAxisAlignment.end
                                                : MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              // Chat head (profile picture) for recipient's messages
                                              // Only show for the first message or when messages are separated by time
                                              if (!message.isMe &&
                                                  isFirstInGroup)
                                                GestureDetector(
                                                  onTap: _showChatPersonDetails,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 8.0,
                                                            bottom: 4.0),
                                                    child: CircleAvatar(
                                                      radius: 16,
                                                      backgroundImage:
                                                          _chatPersonAvatarUrl !=
                                                                  null
                                                              ? NetworkImage(
                                                                  _chatPersonAvatarUrl!)
                                                              : null,
                                                      backgroundColor: theme
                                                                  .brightness ==
                                                              Brightness.dark
                                                          ? colorScheme.primary
                                                              .withOpacity(0.2)
                                                          : Colors.grey
                                                              .withOpacity(0.3),
                                                      child: _chatPersonAvatarUrl ==
                                                              null
                                                          ? Icon(Icons.person,
                                                              color: colorScheme
                                                                  .primary,
                                                              size: 16)
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                              // Placeholder for alignment when avatar isn't shown
                                              if (!message.isMe &&
                                                  !isFirstInGroup)
                                                const SizedBox(width: 40),

                                              // The actual message bubble
                                              Flexible(
                                                child: ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                    maxWidth: message.isMe
                                                        ? maxBubbleWidth
                                                        : maxBubbleWidth -
                                                            40, // Reduce width for recipient's messages to account for avatar
                                                  ),
                                                  child: GestureDetector(
                                                    onLongPress: () {
                                                      // Show message options with haptic feedback
                                                      HapticFeedback
                                                          .mediumImpact();
                                                      _showMessageOptions(
                                                          message);
                                                    },
                                                    child: AnimatedContainer(
                                                      duration: const Duration(
                                                          milliseconds: 200),
                                                      margin:
                                                          const EdgeInsets.only(
                                                              bottom: 4),
                                                      child: ModernMessageBubble(
                                                        message: message.text,
                                                        time: DateFormat('HH:mm').format(message.timestamp),
                                                        isMe: message.isMe,
                                                        isRead: message.isRead,
                                                        bubbleStyle: 'Modern',
                                                        primaryColor: Theme.of(context).primaryColor,
                                                        borderRadius: const BorderRadius.all(Radius.circular(18)),
                                                        reactions: message.reactions,
                                                        currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
                                                        onReactionAdd: (emoji) {
                                                          _toggleMessageReaction(message.id, emoji);
                                                        },
                                                        onLongPress: () {
                                                          _showReactionPicker(message);
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                );
                              },
                            ),
                          );
                        }

                        return _buildEmptyChat();
                      },
                    );
                    },
                  ),
                ),
              ),

              // Message input field
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? colorScheme.surfaceVariant.withOpacity(0.5)
                      : theme.scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      offset: const Offset(0, -1),
                      blurRadius: 5,
                      color: Colors.black.withOpacity(0.1),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Attachment button with subtle animation
                          Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: IconButton(
                              icon: Icon(
                                Icons.add_circle_outline,
                                color: colorScheme.primary,
                              ),
                              onPressed: _showAttachmentOptions,
                              tooltip: 'Attach',
                              splashColor: colorScheme.primary.withOpacity(0.2),
                            ),
                          ),
                          // Expandable text field
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              child: TextField(
                                controller: _messageController,
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24.0),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: theme.brightness == Brightness.dark
                                      ? colorScheme.surface.withOpacity(0.6)
                                      : colorScheme.surface,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 10.0,
                                  ),
                                  // Emoji button
                                  suffixIcon: Material(
                                    color: Colors.transparent,
                                    shape: const CircleBorder(),
                                    clipBehavior: Clip.antiAlias,
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.emoji_emotions_outlined,
                                        color: _isEmojiPickerOpen
                                            ? Colors.amber
                                            : Colors.grey,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isEmojiPickerOpen =
                                              !_isEmojiPickerOpen;
                                          if (_isEmojiPickerOpen) {
                                            // If emoji picker is opened, hide keyboard
                                            FocusScope.of(context).unfocus();
                                          }
                                        });
                                      },
                                      tooltip: 'Emoji',
                                    ),
                                  ),
                                ),
                                textCapitalization:
                                    TextCapitalization.sentences,
                                maxLines: 5,
                                minLines: 1,
                                keyboardType: TextInputType.multiline,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                onTap: () {
                                  // Hide emoji picker when text field is tapped
                                  if (_isEmojiPickerOpen) {
                                    setState(() {
                                      _isEmojiPickerOpen = false;
                                    });
                                  }
                                  // Remove the auto-scroll that was causing issues
                                },
                                // Add focus listener for better keyboard handling
                                onEditingComplete: () {
                                  // Ensure scroll position is maintained
                                  _ensureScrollPosition();
                                },
                              ),
                            ),
                          ),
                          // Send button with animation
                          AnimatedBuilder(
                            animation: _sendButtonAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _messageController.text.isNotEmpty
                                    ? 1.0
                                    : 0.8,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.only(left: 2.0),
                                  decoration: BoxDecoration(
                                    color: _messageController.text.isEmpty
                                        ? colorScheme.primary.withOpacity(0.5)
                                        : colorScheme.primary,
                                    shape: BoxShape.circle,
                                    boxShadow:
                                        _messageController.text.isNotEmpty
                                            ? [
                                                BoxShadow(
                                                  color: colorScheme.primary
                                                      .withOpacity(0.4),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                )
                                              ]
                                            : null,
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    shape: const CircleBorder(),
                                    clipBehavior: Clip.antiAlias,
                                    child: IconButton(
                                      // Removed spinner icon during send; always show send icon
                                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                                      onPressed: (_messageController.text.isNotEmpty && !_isSending)
                                          ? _sendMessage
                                          : () {
                                              // Subtle indication that user needs to enter text
                                              HapticFeedback.lightImpact();
                                            },
                                      tooltip: 'Send',
                                      splashColor: Colors.white24,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      // Emoji picker
                      if (_isEmojiPickerOpen)
                        SizedBox(
                          height: 250,
                          child: EmojiPicker(
                            onEmojiSelected: (category, emoji) {
                              // Fix the double emoji issue by preventing duplicate insertions
                              // Only update the text field once with the selected emoji
                              final text = _messageController.text;
                              final selection = _messageController.selection;
                              final newText = text.replaceRange(
                                selection.start,
                                selection.end,
                                emoji.emoji,
                              );
                              _messageController.text = newText;
                              _messageController.selection =
                                  TextSelection.collapsed(
                                offset: selection.start + emoji.emoji.length,
                              );
                            },
                            onBackspacePressed: () {
                              if (_messageController.text.isNotEmpty) {
                                final text = _messageController.text;
                                final selection = _messageController.selection;
                                if (selection.start > 0) {
                                  final newText = text.replaceRange(
                                    selection.start - 1,
                                    selection.end,
                                    '',
                                  );
                                  _messageController.text = newText;
                                  _messageController.selection =
                                      TextSelection.collapsed(
                                    offset: selection.start - 1,
                                  );
                                }
                              }
                            },
                            textEditingController: _messageController,
                            config: Config(
                              height: 256,
                              checkPlatformCompatibility: true,
                              emojiViewConfig: EmojiViewConfig(
                                columns: 8,
                                emojiSizeMax: 32.0,
                                backgroundColor:
                                    theme.brightness == Brightness.dark
                                        ? colorScheme.surface
                                        : Colors.white,
                                gridPadding: const EdgeInsets.all(2),
                                buttonMode: ButtonMode.MATERIAL,
                              ),
                              categoryViewConfig: CategoryViewConfig(
                                backgroundColor:
                                    theme.brightness == Brightness.dark
                                        ? colorScheme.surfaceVariant
                                        : Colors.white,
                                iconColorSelected: colorScheme.primary,
                                iconColor: Colors.grey,
                                tabIndicatorAnimDuration: kTabScrollDuration,
                                recentTabBehavior: RecentTabBehavior.RECENT,
                                initCategory: Category.RECENT,
                                categoryIcons: const CategoryIcons(
                                  recentIcon: Icons.access_time_rounded,
                                  smileyIcon: Icons.emoji_emotions_outlined,
                                  animalIcon: Icons.pets_outlined,
                                  foodIcon: Icons.fastfood_outlined,
                                  travelIcon: Icons.location_on_outlined,
                                  activityIcon: Icons.sports_soccer_outlined,
                                  objectIcon: Icons.lightbulb_outline,
                                  symbolIcon: Icons.emoji_symbols_outlined,
                                  flagIcon: Icons.flag_outlined,
                                ),
                              ),
                              skinToneConfig: SkinToneConfig(
                                enabled: true,
                                dialogBackgroundColor: Colors.white,
                              ),
                              bottomActionBarConfig: BottomActionBarConfig(
                                backgroundColor:
                                    theme.brightness == Brightness.dark
                                        ? colorScheme.surfaceVariant
                                        : Colors.white,
                                buttonColor: colorScheme.primary,
                                buttonIconColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showReactionPicker(Message message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'React to message',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                MessageReactionPicker(
                  onEmojiSelected: (emoji) {
                    Navigator.of(context).pop();
                    _toggleMessageReaction(message.id, emoji);
                  },
                  onDismiss: () {
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showMessageOptions(message);
                  },
                  child: const Text('More options'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
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

  Future<void> _toggleMessageReaction(String messageId, String emoji) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      await _chatService.toggleMessageReaction(
        widget.chatId,
        messageId,
        emoji,
        user.uid,
        user.displayName ?? 'Anonymous',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add reaction: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAttachmentOptions() {
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
    
    // Clear input immediately for better UX (optimistic)
    _messageController.clear();

    // Reset reply state and prevent double-send (no spinner UI)
    setState(() {
      _isSending = true;
      _replyingTo = '';
    });

    // Scroll to bottom with slight delay to avoid keyboard conflicts
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });

    try {
      // Send message to Firebase
      await _chatService.sendMessage(
        widget.chatId,
        messageText,
        user!.uid,
      );

    } catch (e) {
      // Enhanced error handling with user-friendly messages
      String errorMessage = UserFriendlyErrorHandler.getReadableErrorMessage(e.toString());
      
      // Restore message text for retry
      _messageController.text = messageText;
      
      // Show error with retry option
      _showRetrySnackBar(errorMessage, messageText);
      
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // Show quick feedback for user actions
  void _showQuickFeedback(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  // Show error with retry functionality
  void _showRetrySnackBar(String errorMessage, String originalMessage) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              // Restore message and try again
              _messageController.text = originalMessage;
              _sendMessage();
            },
          ),
        ),
      );
    }
  }

  // Auto-refresh functionality for real-time experience
  Future<void> _refreshChatData() async {
    try {
      // Refresh chat person details
      await _loadChatPersonDetails();
      
      // Refresh usernames cache
      await _cacheUsernames();
      
    } catch (e) {
      _showQuickFeedback('Failed to refresh', Colors.orange);
    }
  }

  // Build connection status indicator for Ajax-type system
  Widget _buildConnectionIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _isConnected 
        ? Icon(
            Icons.wifi,
            size: 16,
            color: theme.brightness == Brightness.dark ? Colors.green : Colors.white,
          )
        : GestureDetector(
            onTap: _checkConnectionAndRefresh,
            child: Icon(
              Icons.wifi_off,
              size: 16,
              color: theme.brightness == Brightness.dark ? Colors.red : Colors.orange,
            ),
          ),
    );
  }

  // Check connection status and refresh if needed
  Future<void> _checkConnectionAndRefresh() async {
    try {
      // Simple connectivity test
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
      
      if (!_isConnected) {
        setState(() {
          _isConnected = true;
        });
        _showQuickFeedback('Connection restored!', Colors.green);
      }
      
      // Auto-refresh data
      await _refreshChatData();
    } catch (e) {
      setState(() {
        _isConnected = false;
      });
      _showQuickFeedback('No internet connection', Colors.red);
    }
  }

  // Initialize connection monitoring
  void _startConnectionMonitoring() {
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _checkConnectionAndRefresh();
    });
  }

  // Start an audio call
  Future<void> _startAudioCall() async {
    final CallService callService = CallService();

    try {
      // Initialize the call service if it hasn't been already
      await callService.initialize();

      // Get the chat participant's ID (the person to call)
      DocumentSnapshot chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();

      if (!chatDoc.exists) {
        throw Exception('Chat not found');
      }

      List<dynamic> userIds = chatDoc['userIds'];
      String calleeId = "";

      // Find the other user in the chat
      for (var id in userIds) {
        if (id != user!.uid) {
          calleeId = id;
          break;
        }
      }

      if (calleeId.isEmpty) {
        throw Exception('Call recipient not found');
      }

      // Show loading indicator
      setState(() {
        _isSending = true; // Reuse the sending indicator for loading
      });

      // Start the call
      Call? call = await callService.startCall(
          calleeId, false); // false = audio call, not video

      setState(() {
        _isSending = false;
      });

      if (call == null) {
        throw Exception('Failed to start call');
      }

      // Navigate to the call screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AudioCallScreen(
              call: call,
              isIncoming: false,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSending = false;
      });

      print('Error starting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start call: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Start a video call
  Future<void> _startVideoCall() async {
    final CallService callService = CallService();

    try {
      // Initialize the call service if it hasn't been already
      await callService.initialize();

      // Get the chat participant's ID (the person to call)
      DocumentSnapshot chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();

      if (!chatDoc.exists) {
        throw Exception('Chat not found');
      }

      List<dynamic> userIds = chatDoc['userIds'];
      String calleeId = "";

      // Find the other user in the chat
      for (var id in userIds) {
        if (id != user!.uid) {
          calleeId = id;
          break;
        }
      }

      if (calleeId.isEmpty) {
        throw Exception('Call recipient not found');
      }

      // Show loading indicator
      setState(() {
        _isSending = true; // Reuse the sending indicator for loading
      });

      // Start the call
      Call? call = await callService.startCall(
          calleeId, true); // true = video call, not audio only

      setState(() {
        _isSending = false;
      });

      if (call == null) {
        throw Exception('Failed to start call');
      }

      // Navigate to the call screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoCallScreen(
              call: call,
              isIncoming: false,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSending = false;
      });

      print('Error starting video call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start video call: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildEmptyChat() {
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

  // Add keyboard listener setup method
  void _setupKeyboardListener() {
    // Listen to keyboard visibility changes
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    
    // Store initial keyboard state
    _lastKeyboardHeight = keyboardHeight;
  }

  // Add keyboard change handler
  void _handleKeyboardChange(bool isKeyboardAppearing) {
    if (_isKeyboardAnimating) return;
    
    _isKeyboardAnimating = true;
    
    if (isKeyboardAppearing) {
      // Keyboard is appearing - gently scroll to show recent messages
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients && mounted) {
          _scrollController.animateTo(
            0, // Scroll to the most recent message
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ).then((_) {
            _isKeyboardAnimating = false;
          });
        } else {
          _isKeyboardAnimating = false;
        }
      });
    } else {
      // Keyboard is disappearing - maintain current position
      Future.delayed(const Duration(milliseconds: 100), () {
        _isKeyboardAnimating = false;
      });
    }
  }

  // Add scroll position maintenance method
  void _ensureScrollPosition() {
    if (_scrollController.hasClients && mounted) {
      // Maintain current scroll position without jarring movements
      final currentPosition = _scrollController.position.pixels;
      
      // Only adjust if we're very close to the bottom (within 100 pixels)
      if (currentPosition < 100) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients && mounted) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }
}
