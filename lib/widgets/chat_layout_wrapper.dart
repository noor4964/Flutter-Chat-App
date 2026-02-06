import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/views/chat/chat_list_screen.dart';
import 'package:flutter_chat_app/views/chat/chat_screen.dart';
import 'package:flutter_chat_app/views/user_profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatLayoutWrapper extends StatefulWidget {
  final bool isDesktop;

  const ChatLayoutWrapper({
    Key? key,
    this.isDesktop = false,
  }) : super(key: key);

  @override
  _ChatLayoutWrapperState createState() => _ChatLayoutWrapperState();
}

class _ChatLayoutWrapperState extends State<ChatLayoutWrapper> with TickerProviderStateMixin {
  String? _selectedChatId;
  String? _selectedUserId;
  String? _selectedUserName;
  String? _selectedUserImageUrl;
  bool _selectedUserIsOnline = false;
  bool _isSidebarCollapsed = false;
  late AnimationController _sidebarAnimationController;
  late Animation<double> _sidebarAnimation;

  @override
  void initState() {
    super.initState();
    _sidebarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _sidebarAnimation = Tween<double>(
      begin: 320.0, // Full width
      end: 60.0,    // Collapsed width
    ).animate(CurvedAnimation(
      parent: _sidebarAnimationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _sidebarAnimationController.dispose();
    super.dispose();
  }

  void _toggleSidebar([bool? forceCollapse]) {
    setState(() {
      if (forceCollapse != null) {
        _isSidebarCollapsed = forceCollapse;
      } else {
        _isSidebarCollapsed = !_isSidebarCollapsed;
      }
      
      if (_isSidebarCollapsed) {
        _sidebarAnimationController.forward();
      } else {
        _sidebarAnimationController.reverse();
      }
    });
  }

  Future<void> _onChatSelected(String chatId, String chatName, String? profileImageUrl, bool isOnline) async {
    print('🔍 Chat selected: $chatId, $chatName, $profileImageUrl, $isOnline');
    
    // Set user data immediately from the passed parameters
    setState(() {
      _selectedChatId = chatId;
      _selectedUserName = chatName;
      _selectedUserImageUrl = profileImageUrl;
      _selectedUserIsOnline = isOnline;
    });
    
    // Collapse sidebar when chat is selected
    _toggleSidebar(true);
  }

  void _onBackToChats() {
    setState(() {
      _selectedChatId = null;
      _selectedUserId = null;
      _selectedUserName = null;
      _selectedUserImageUrl = null;
      _selectedUserIsOnline = false;
    });
    // Expand sidebar when going back
    _toggleSidebar(false);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // For web platforms with sufficient width, use the three-column layout
    if (PlatformHelper.isWeb && screenWidth >= 1200) {
      return _buildWebLayout();
    }
    
    // For mobile or small screens, use traditional navigation
    return _buildMobileLayout();
  }

  Widget _buildWebLayout() {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // Left: Animated Chat List Sidebar
          AnimatedBuilder(
            animation: _sidebarAnimation,
            builder: (context, child) {
              return Container(
                width: _sidebarAnimation.value,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    right: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 1,
                    ),
                  ),
                ),
                child: _isSidebarCollapsed 
                  ? _buildCollapsedSidebar()
                  : _buildFullSidebar(),
              );
            },
          ),
          
          // Center: Chat Conversation (flexible width)
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Header with toggle button
                  if (_selectedChatId != null) _buildChatHeader(),
                  // Chat content
                  Expanded(
                    child: _selectedChatId != null 
                      ? ChatScreen(
                          chatId: _selectedChatId!, 
                          hideHeader: true,
                          chatPersonName: _selectedUserName,
                          chatPersonAvatarUrl: _selectedUserImageUrl,
                          chatPersonIsOnline: _selectedUserIsOnline,
                        )
                      : _buildEmptyChatView(),
                  ),
                ],
              ),
            ),
          ),
          
          // Right: User Profile (300px width)  
          Container(
            width: 300,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
            ),
            child: _selectedUserId != null && _selectedUserName != null && _selectedUserImageUrl != null
              ? UserProfileScreen(
                  profileImageUrl: _selectedUserImageUrl!,
                  username: _selectedUserName!,
                  isOnline: _selectedUserIsOnline,
                )
              : _buildEmptyProfileView(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    // Traditional mobile layout - just show chat list initially
    if (_selectedChatId == null) {
      return ChatListScreen(
        isDesktop: false,
        onChatSelected: (chatId, chatName, profileImageUrl, isOnline) {
          // Navigate to individual chat screen on mobile
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(chatId: chatId),
            ),
          );
        },
      );
    } else {
      // This shouldn't happen in mobile layout, but just in case
      return ChatScreen(chatId: _selectedChatId!);
    }
  }



  Widget _buildEmptyChatView() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Select a chat to start messaging',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).disabledColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a conversation from the list to view messages',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyProfileView() {
    return Container(
      color: Theme.of(context).cardColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 80,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No chat selected',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).disabledColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a chat to view profile',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullSidebar() {
    return ChatListScreen(
      isDesktop: true,
      hideAppBar: true,
      onChatSelected: (chatId, chatName, profileImageUrl, isOnline) {
        _onChatSelected(chatId, chatName, profileImageUrl, isOnline);
      },
    );
  }

  Widget _buildCollapsedSidebar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          // Toggle button to expand
          IconButton(
            onPressed: () => _toggleSidebar(false),
            icon: const Icon(Icons.menu),
            tooltip: 'Expand chat list',
          ),
          const Divider(),
          // Recent chats icons (you can add more functionality here)
          if (_selectedChatId != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: CircleAvatar(
                radius: 20,
                backgroundImage: _selectedUserImageUrl != null 
                  ? NetworkImage(_selectedUserImageUrl!)
                  : null,
                child: _selectedUserImageUrl == null 
                  ? Text(_selectedUserName?.substring(0, 1).toUpperCase() ?? '?')
                  : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Toggle sidebar button (only show when collapsed)
          if (_isSidebarCollapsed)
            IconButton(
              onPressed: () => _toggleSidebar(false),
              icon: const Icon(Icons.menu),
              tooltip: 'Show chat list',
            ),
          
          // User info
          if (_selectedUserImageUrl != null)
            CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(_selectedUserImageUrl!),
            )
          else
            CircleAvatar(
              radius: 18,
              child: Text(_selectedUserName?.substring(0, 1).toUpperCase() ?? '?'),
            ),
          
          const SizedBox(width: 12),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _selectedUserName ?? 'Unknown User',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _selectedUserIsOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: _selectedUserIsOnline ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          
          // Action buttons
          IconButton(
            onPressed: () {
              // Handle voice call
            },
            icon: const Icon(Icons.call),
            tooltip: 'Voice call',
          ),
          
          IconButton(
            onPressed: () {
              // Handle video call
            },
            icon: const Icon(Icons.videocam),
            tooltip: 'Video call',
          ),
          
          IconButton(
            onPressed: () {
              // Handle more options
            },
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
          ),
        ],
      ),
    );
  }
}