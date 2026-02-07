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
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';
import 'package:flutter_chat_app/providers/call_provider.dart';
import 'package:flutter_chat_app/views/calls/audio_call_screen.dart';
import 'package:flutter_chat_app/views/calls/video_call_screen.dart';
import 'dart:async';
import '../../../utils/user_friendly_error_handler.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';

enum MessageStatus {
  sending,
  sent,
  seen,
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final bool hideHeader;
  final String? chatPersonName;
  final String? chatPersonAvatarUrl;
  final bool? chatPersonIsOnline;

  const ChatScreen({
    super.key, 
    required this.chatId, 
    this.hideHeader = false,
    this.chatPersonName,
    this.chatPersonAvatarUrl,
    this.chatPersonIsOnline,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
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

  // WhatsApp-style real-time system variables
  bool _isConnected = true; // Connection status for subtle feedback only

  // Cached chat person ID — used for typing, online status, and calls
  String? _chatPersonId;

  // Stream subscription for online status (real-time updates)
  StreamSubscription<DocumentSnapshot>? _onlineStatusSubscription;

  // For animations
  late AnimationController _sendButtonAnimationController;

  // Group messages by date
  Map<String, List<Message>> _groupedMessages = {};

  // Cached message stream — created once in initState, never recreated
  Stream<List<Message>>? _messagesStream;

  // Memoization fields for _groupMessagesByDate
  int _lastGroupedMessageCount = -1;
  String? _lastGroupedFirstMessageId;

  // Debouncer for mark-as-read (replaces aggressive 1-second timer)
  Timer? _markAsReadDebouncer;

  // Track whether usernames have been cached
  bool _usernamesCached = false;

  // Keyboard state tracking for consistent scrolling (mobile only)
  double _lastKeyboardHeight = 0.0;
  bool _isKeyboardAnimating = false;

  @override
  void initState() {
    super.initState();
    
    // Add app lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    // Use passed parameters if available, otherwise load from Firebase
    if (widget.chatPersonName != null) {
      _chatPersonName = widget.chatPersonName;
      _chatPersonAvatarUrl = widget.chatPersonAvatarUrl;
      _chatPersonIsOnline = widget.chatPersonIsOnline ?? false;
    } else {
      _loadChatPersonDetails();
    }
    
    // Cache usernames once (not on every build)
    _cacheUsernamesOnce();

    // Create message stream ONCE — reused across rebuilds
    if (user != null) {
      _messagesStream = _chatService.getMessages(widget.chatId, user!.uid);
    }

    // Debounced mark-as-read (replaces aggressive 1-second timer)
    _debouncedMarkAsRead();

    // Update presence to show that user is in this chat
    _updatePresence(true);

    // Initialize animation controller for send button
    _sendButtonAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Listen to text changes to animate send button
    _messageController.addListener(_onMessageTextChanged);

    // Auto-focus message input so user can start typing immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _messageFocusNode.requestFocus();
      // Set up keyboard listener (mobile only)
      if (!kIsWeb) _setupKeyboardListener();
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
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If chatId changed (e.g., web layout reused this widget), reinitialize everything
    if (widget.chatId != oldWidget.chatId) {
      // Cancel old subscriptions
      _onlineStatusSubscription?.cancel();
      _onlineStatusSubscription = null;
      _markAsReadDebouncer?.cancel();
      _markAsReadDebouncer = null;

      // Clear typing status for old chat
      if (user != null) {
        _chatService.setTypingStatus(oldWidget.chatId, user!.uid, false);
      }

      // Reset cached state
      _usernamesCached = false;
      _usernamesCache = {};
      _chatPersonId = null;
      _lastGroupedMessageCount = -1;
      _lastGroupedFirstMessageId = null;
      _groupedMessages.clear();
      _isTyping = false;
      _replyingTo = '';
      _messageController.clear();

      // Update person info from new widget params
      if (widget.chatPersonName != null) {
        _chatPersonName = widget.chatPersonName;
        _chatPersonAvatarUrl = widget.chatPersonAvatarUrl;
        _chatPersonIsOnline = widget.chatPersonIsOnline ?? false;
      } else {
        _loadChatPersonDetails();
      }

      // Recreate message stream for new chat
      if (user != null) {
        _messagesStream = _chatService.getMessages(widget.chatId, user!.uid);
      }

      // Reinitialize
      _cacheUsernamesOnce();
      _debouncedMarkAsRead();
      _updatePresence(true);

      setState(() {});
    }
  }

  @override
  void dispose() {
    // Remove app lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Clear typing status on dispose
    if (user != null) {
      _chatService.setTypingStatus(widget.chatId, user!.uid, false);
    }

    // Update presence to show that user is no longer in this chat
    _updatePresence(false);

    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _sendButtonAnimationController.dispose();

    // Cancel mark-as-read debouncer
    _markAsReadDebouncer?.cancel();

    // Cancel online status listener
    _onlineStatusSubscription?.cancel();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Mark messages as read when app becomes active (user returns to chat)
    if (state == AppLifecycleState.resumed) {
      _debouncedMarkAsRead();
    }
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
          // Store for reuse in calls
          _chatPersonId = chatPersonId;

          DocumentSnapshot userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(chatPersonId)
              .get();
          if (userDoc.exists && mounted) {
            final userData = userDoc.data() as Map<String, dynamic>?;
            
            // Only update values we don't have from passed parameters
            setState(() {
              if (widget.chatPersonName == null) {
                _chatPersonName = userData?['username'];
              }
              if (widget.chatPersonAvatarUrl == null) {
                _chatPersonAvatarUrl =
                    userData != null && userData.containsKey('profileImageUrl')
                        ? userData['profileImageUrl']
                        : null;
              }
              if (widget.chatPersonIsOnline == null) {
                _chatPersonIsOnline = userData?['isOnline'] ?? false;
              }
            });

            // Start listening to typing status
            _listenToTypingStatus(chatPersonId);

            // Start real-time online status listener
            _listenToOnlineStatus(chatPersonId);
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

  /// Cache usernames exactly once (not on every build).
  /// Also extracts and stores _chatPersonId, starts typing + online status listeners.
  Future<void> _cacheUsernamesOnce() async {
    if (_usernamesCached || user == null) return;
    _usernamesCached = true;
    try {
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

            // Store the chat person ID for reuse (typing, online status, calls)
            if (_chatPersonId == null) {
              _chatPersonId = userId;

              // Start typing status listener (critical for web where _loadChatPersonDetails is skipped)
              _listenToTypingStatus(userId);

              // Start real-time online status listener
              _listenToOnlineStatus(userId);
            }
          }
        }
      }
    } catch (e) {
      _usernamesCached = false; // Allow retry on error
    }
  }

  /// Listen to the chat person's online/offline status in real-time
  void _listenToOnlineStatus(String chatPersonId) {
    _onlineStatusSubscription?.cancel();
    _onlineStatusSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(chatPersonId)
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>?;
        final isOnline = data?['isOnline'] ?? false;
        if (isOnline != _chatPersonIsOnline) {
          setState(() {
            _chatPersonIsOnline = isOnline;
          });
        }
        // Also update avatar/name if they changed (and we don't have them)
        if (_chatPersonAvatarUrl == null && data?.containsKey('profileImageUrl') == true) {
          setState(() {
            _chatPersonAvatarUrl = data!['profileImageUrl'];
          });
        }
      }
    });
  }

  /// Debounced mark-as-read — waits 1.5s of inactivity before firing.
  /// Replaces the aggressive 1-second Timer.periodic that caused 2+ Firestore writes/sec.
  void _debouncedMarkAsRead() {
    _markAsReadDebouncer?.cancel();
    _markAsReadDebouncer = Timer(const Duration(milliseconds: 1500), () {
      _doMarkAsRead();
    });
  }

  /// Actually perform the mark-as-read write (called by debouncer only)
  Future<void> _doMarkAsRead() async {
    if (user != null && mounted) {
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

  /// Memoized grouping — skips expensive clear+rebuild when messages haven't changed
  void _groupMessagesByDate(List<Message> messages) {
    // Quick identity check: if count and first message ID match, skip re-grouping
    final firstId = messages.isNotEmpty ? messages.first.id : null;
    if (messages.length == _lastGroupedMessageCount &&
        firstId == _lastGroupedFirstMessageId &&
        _groupedMessages.isNotEmpty) {
      return; // No change — reuse existing grouping
    }
    _lastGroupedMessageCount = messages.length;
    _lastGroupedFirstMessageId = firstId;

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
    _messageFocusNode.requestFocus();
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
    
    // Check if we're in web layout mode (large screen)
    bool isWebLayout = PlatformHelper.isWeb && MediaQuery.of(context).size.width >= 1200;
    bool shouldHideHeader = widget.hideHeader || isWebLayout;
    
    // Track keyboard height changes for consistent scrolling (mobile only — web has no viewInsets)
    if (!kIsWeb) {
      final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
      
      // Handle keyboard appearance/disappearance — check inline, no addPostFrameCallback
      if (keyboardHeight != _lastKeyboardHeight && !_isKeyboardAnimating) {
        final wasAppearing = keyboardHeight > _lastKeyboardHeight;
        _lastKeyboardHeight = keyboardHeight;
        // Schedule microtask to avoid setState-during-build
        Future.microtask(() {
          if (mounted) _handleKeyboardChange(wasAppearing);
        });
      }
    }

    return Scaffold(
      // Only show AppBar when not hiding header and not in web layout  
      appBar: shouldHideHeader ? null : AppBar(
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
              Stack(
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final containerWidth = constraints.maxWidth;
                    return Container(
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
                  // Use container width (not screen width) for correct padding in web panels
                  padding: isTabletOrDesktop
                      ? EdgeInsets.symmetric(
                          horizontal: containerWidth * 0.05)
                      : EdgeInsets.zero,
                  child: StreamBuilder<List<Message>>(
                        stream: _messagesStream,
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

                            // Group messages by date (memoized — skips if unchanged)
                            _groupMessagesByDate(messages);

                            // Trigger debounced mark-as-read whenever new data arrives
                            _debouncedMarkAsRead();

                            // Only show empty chat if we explicitly have empty data
                            if (messages.isEmpty) {
                              return _buildEmptyChat();
                            }

                            // Add smooth real-time updates without refresh indicator
                            return ListView.builder(
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

                                // Calculate max width for bubbles using container width (not screen width)
                                final maxBubbleWidth = isTabletOrDesktop
                                    ? containerWidth * 0.6 // 60% on larger screens
                                    : containerWidth * 0.75; // 75% on mobile

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

                                      return Material(
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
                                                      // Show message options with haptic feedback (skip on web)
                                                      if (!kIsWeb) HapticFeedback.mediumImpact();
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
                                                        messageType: message.type,
                                                        imageUrl: message.type == 'image' ? message.text : null,
                                                        messageData: _getMessageData(message),
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
                                      );
                                    }).toList(),
                                  ],
                                );
                              },
                            );
                        }

                        return _buildEmptyChat();
                      },
                    ),
                );
                  },
                ),
              ),

              // Message input field
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? colorScheme.surface
                      : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      offset: const Offset(0, -1),
                      blurRadius: 10,
                      color: Colors.black.withOpacity(0.04),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      // Unified capsule input bar
                      Container(
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark
                              ? colorScheme.surfaceContainerHighest.withOpacity(0.5)
                              : const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.black.withOpacity(0.04),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Attachment button inside capsule
                            Padding(
                              padding: const EdgeInsets.only(left: 6, bottom: 6),
                              child: SizedBox(
                                width: 38,
                                height: 38,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.add_rounded,
                                    color: colorScheme.primary,
                                    size: 22,
                                  ),
                                  onPressed: _showAttachmentOptions,
                                  tooltip: 'Attach',
                                  padding: EdgeInsets.zero,
                                  splashRadius: 18,
                                ),
                              ),
                            ),
                            // Expandable text field
                            Expanded(
                              child: Focus(
                                onKeyEvent: kIsWeb ? (node, event) {
                                  if (event is KeyDownEvent &&
                                      event.logicalKey == LogicalKeyboardKey.enter &&
                                      !HardwareKeyboard.instance.isShiftPressed) {
                                    if (_messageController.text.trim().isNotEmpty && !_isSending) {
                                      _sendMessage();
                                    }
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                } : null,
                                child: TextField(
                                  controller: _messageController,
                                  focusNode: _messageFocusNode,
                                  decoration: InputDecoration(
                                    hintText: 'Type a message...',
                                    hintStyle: TextStyle(
                                      color: colorScheme.onSurface.withOpacity(0.35),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                      vertical: 10.0,
                                    ),
                                  ),
                                  textCapitalization: TextCapitalization.sentences,
                                  maxLines: 5,
                                  minLines: 1,
                                  keyboardType: TextInputType.multiline,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    height: 1.35,
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white
                                        : const Color(0xFF1A1A1A),
                                  ),
                                  onTap: () {
                                    if (_isEmojiPickerOpen) {
                                      setState(() {
                                        _isEmojiPickerOpen = false;
                                      });
                                    }
                                  },
                                  onEditingComplete: () {
                                    _ensureScrollPosition();
                                  },
                                  autofocus: false,
                                ),
                              ),
                            ),
                            // Emoji button inside capsule
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: SizedBox(
                                width: 38,
                                height: 38,
                                child: IconButton(
                                  icon: Icon(
                                    _isEmojiPickerOpen
                                        ? Icons.keyboard_rounded
                                        : Icons.emoji_emotions_outlined,
                                    color: _isEmojiPickerOpen
                                        ? Colors.amber
                                        : colorScheme.onSurface.withOpacity(0.4),
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isEmojiPickerOpen = !_isEmojiPickerOpen;
                                      if (_isEmojiPickerOpen) {
                                        FocusScope.of(context).unfocus();
                                      }
                                    });
                                  },
                                  tooltip: 'Emoji',
                                  padding: EdgeInsets.zero,
                                  splashRadius: 18,
                                ),
                              ),
                            ),
                            // Gradient send button
                            Padding(
                              padding: const EdgeInsets.only(right: 5, bottom: 5),
                              child: AnimatedScale(
                                scale: _messageController.text.isNotEmpty ? 1.0 : 0.85,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: _messageController.text.isEmpty
                                          ? [
                                              colorScheme.primary.withOpacity(0.4),
                                              colorScheme.primary.withOpacity(0.3),
                                            ]
                                          : [
                                              colorScheme.primary,
                                              HSLColor.fromColor(colorScheme.primary)
                                                  .withHue((HSLColor.fromColor(colorScheme.primary).hue + 18) % 360)
                                                  .withLightness((HSLColor.fromColor(colorScheme.primary).lightness - 0.06).clamp(0.0, 1.0))
                                                  .toColor(),
                                            ],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: _messageController.text.isNotEmpty
                                        ? [
                                            BoxShadow(
                                              color: colorScheme.primary.withOpacity(0.35),
                                              blurRadius: 10,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    shape: const CircleBorder(),
                                    clipBehavior: Clip.antiAlias,
                                    child: IconButton(
                                      icon: const Icon(Icons.send_rounded,
                                          color: Colors.white, size: 20),
                                      onPressed: (_messageController.text.isNotEmpty && !_isSending)
                                          ? _sendMessage
                                          : () {
                                              if (!kIsWeb) HapticFeedback.lightImpact();
                                            },
                                      tooltip: 'Send',
                                      padding: EdgeInsets.zero,
                                      splashColor: Colors.white24,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                      _pickImageFromGallery();
                    },
                  ),
                  // Camera not available on web
                  if (!kIsWeb)
                    _buildAttachmentOption(
                      icon: Icons.camera_alt,
                      label: 'Camera',
                      color: Colors.red,
                      onTap: () {
                        Navigator.pop(context);
                        _takePictureWithCamera();
                      },
                    ),
                  _buildAttachmentOption(
                    icon: Icons.insert_drive_file,
                    label: 'Document',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      _pickDocument();
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.location_on,
                    label: 'Location',
                    color: Colors.green,
                    onTap: () {
                      Navigator.pop(context);
                      _shareLocation();
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

    // Keep focus on the text field so user can keep typing
    _messageFocusNode.requestFocus();

    // Reset reply state and prevent double-send (no spinner UI)
    setState(() {
      _isSending = true;
      _replyingTo = '';
    });

    // Immediate scroll to bottom for instant feedback
    _scrollToBottom();

    try {
      // Send message to Firebase - optimized for performance
      await _chatService.sendMessage(
        widget.chatId,
        messageText,
        user!.uid,
      );

      // Message sent successfully - no need for success notification
      // The real-time listener will update the UI automatically

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

  // Minimal data sync for when absolutely necessary (like after reconnection)
  Future<void> _refreshChatData() async {
    try {
      // Only refresh critical data if needed - Firestore listeners handle most updates
      if (!_isConnected) {
        await _checkConnectionAndRefresh();
      }
    } catch (e) {
      // Silent failure - let Firestore listeners handle the updates
    }
  }

  // Build subtle connection status indicator like WhatsApp
  Widget _buildConnectionIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _isConnected 
        ? const SizedBox.shrink() // Hidden when connected, like WhatsApp
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  'Connecting...',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
    );
  }

  // Check connection status silently like WhatsApp
  Future<void> _checkConnectionAndRefresh() async {
    try {
      // Simple connectivity test without forcing refresh
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
      
      if (!_isConnected) {
        setState(() {
          _isConnected = true;
        });
        // No intrusive feedback - just silently reconnect
      }
    } catch (e) {
      if (_isConnected) {
        setState(() {
          _isConnected = false;
        });
        // Only show subtle feedback when connection is lost
      }
    }
  }

  // Start an audio call
  Future<void> _startAudioCall() async {
    final callProvider = Provider.of<CallProvider>(context, listen: false);

    try {
      // Use cached chatPersonId to avoid redundant Firestore read
      String calleeId = _chatPersonId ?? '';
      if (calleeId.isEmpty) {
        // Fallback: fetch from Firestore if not yet cached
        DocumentSnapshot chatDoc = await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .get();

        if (!chatDoc.exists) {
          throw Exception('Chat not found');
        }

        List<dynamic> userIds = chatDoc['userIds'];
        for (var id in userIds) {
          if (id != user!.uid) {
            calleeId = id;
            _chatPersonId = id; // Cache for future use
            break;
          }
        }
      }

      if (calleeId.isEmpty) {
        throw Exception('Call recipient not found');
      }

      // Show loading indicator
      setState(() {
        _isSending = true;
      });

      // Start the call using CallProvider
      Call? call = await callProvider.startCall(calleeId, false);

      setState(() {
        _isSending = false;
      });

      if (call == null) {
        throw Exception('Failed to start call');
      }

      // Navigate to the audio call screen
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
    final callProvider = Provider.of<CallProvider>(context, listen: false);

    try {
      // Use cached chatPersonId to avoid redundant Firestore read
      String calleeId = _chatPersonId ?? '';
      if (calleeId.isEmpty) {
        // Fallback: fetch from Firestore if not yet cached
        DocumentSnapshot chatDoc = await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .get();

        if (!chatDoc.exists) {
          throw Exception('Chat not found');
        }

        List<dynamic> userIds = chatDoc['userIds'];
        for (var id in userIds) {
          if (id != user!.uid) {
            calleeId = id;
            _chatPersonId = id; // Cache for future use
            break;
          }
        }
      }

      if (calleeId.isEmpty) {
        throw Exception('Call recipient not found');
      }

      // Show loading indicator
      setState(() {
        _isSending = true;
      });

      // Start the call using CallProvider
      Call? call = await callProvider.startCall(calleeId, true);

      setState(() {
        _isSending = false;
      });

      if (call == null) {
        throw Exception('Failed to start call');
      }

      // Navigate to the video call screen
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

  // Pick image from gallery
  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (image != null) {
        await _uploadAndSendImage(image);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: ${e.toString()}');
    }
  }

  // Take picture with camera
  Future<void> _takePictureWithCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (image != null) {
        await _uploadAndSendImage(image);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to take picture: ${e.toString()}');
    }
  }

  // Upload image to Firebase Storage and send message
  Future<void> _uploadAndSendImage(XFile imageFile) async {
    if (user == null) return;

    try {
      // Send image message instantly using WhatsApp-like approach
      await _chatService.sendImageMessageInstant(
        widget.chatId,
        imageFile.path,
        user!.uid,
        imageFile.name,
      );

      _showQuickFeedback('Image sending...', Colors.blue);
    } catch (e) {
      _showErrorSnackBar('Failed to send image: ${e.toString()}');
    }
  }

  // Pick document
  Future<void> _pickDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx', 'ppt', 'pptx'],
        allowMultiple: false,
        withData: kIsWeb, // Request bytes on web since path is null
      );

      if (result != null) {
        final file = result.files.single;
        // On web, path is null but bytes are available; on mobile, path is set
        if (file.path != null || (kIsWeb && file.bytes != null)) {
          await _uploadAndSendDocument(file);
        }
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick document: ${e.toString()}');
    }
  }

  // Upload document to Firebase Storage and send message
  Future<void> _uploadAndSendDocument(PlatformFile documentFile) async {
    if (user == null) return;

    // Check file size (limit to 10MB)
    if (documentFile.size > 10 * 1024 * 1024) {
      _showErrorSnackBar('File size must be less than 10MB');
      return;
    }

    try {
      String? filePath = documentFile.path;
      if (kIsWeb && documentFile.bytes != null) {
        // For web, we need to save bytes to a temporary path
        // This is a simplified approach - in production you might handle this differently
        filePath = documentFile.name;
      } else if (!kIsWeb && documentFile.path == null) {
        throw Exception('Could not access file path');
      }

      // Send document message instantly using WhatsApp-like approach
      await _chatService.sendDocumentMessageInstant(
        widget.chatId,
        filePath!,
        user!.uid,
        documentFile.name,
        documentFile.size,
      );

      _showQuickFeedback('Document sending...', Colors.blue);
    } catch (e) {
      _showErrorSnackBar('Failed to send document: ${e.toString()}');
    }
  }

  // Share current location
  Future<void> _shareLocation() async {
    try {
      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showErrorSnackBar('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showErrorSnackBar('Location permissions are permanently denied. Please enable them in settings.');
        return;
      }

      // Show quick loading feedback
      _showQuickFeedback('Getting location...', Colors.blue);

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Send location message instantly
      await _chatService.sendLocationMessageInstant(
        widget.chatId,
        user!.uid,
        position.latitude,
        position.longitude,
      );

      _showQuickFeedback('Location shared successfully', Colors.green);
    } catch (e) {
      _showErrorSnackBar('Failed to get location: ${e.toString()}');
    }
  }

  // Upload progress and loading indicators
  OverlayEntry? _uploadOverlay;

  void _showUploadingIndicator(String message) {
    _hideUploadingIndicator(); // Remove any existing overlay

    _uploadOverlay = OverlayEntry(
      builder: (context) => Container(
        color: Colors.black54,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_uploadOverlay!);
  }

  void _updateUploadProgress(double progress) {
    // Update progress if needed - for now we just show loading
  }

  void _hideUploadingIndicator() {
    _uploadOverlay?.remove();
    _uploadOverlay = null;
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Helper method to extract message data based on type
  Map<String, dynamic>? _getMessageData(Message message) {
    switch (message.type) {
      case 'document':
        // Extract document data from Firebase document
        return {
          'fileName': 'Document', // Default, will be enhanced when we get data from Firestore
          'fileSize': 0,
        };
      case 'location':
        // Extract location data from message content
        final locationMatch = RegExp(r'Location: (-?\d+\.?\d*), (-?\d+\.?\d*)').firstMatch(message.text);
        if (locationMatch != null) {
          return {
            'latitude': double.tryParse(locationMatch.group(1) ?? '0') ?? 0.0,
            'longitude': double.tryParse(locationMatch.group(2) ?? '0') ?? 0.0,
          };
        }
        return {'latitude': 0.0, 'longitude': 0.0};
      default:
        return null;
    }
  }
}
