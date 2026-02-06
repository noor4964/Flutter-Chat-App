import 'package:flutter/material.dart';
import 'package:flutter_chat_app/views/chat/chat_list_screen.dart';
import 'package:flutter_chat_app/views/chat/chat_screen.dart';
import 'package:flutter_chat_app/widgets/messenger_left_sidebar.dart';

class ChatLayoutWithMainSidebar extends StatefulWidget {
  final bool isDesktop;
  final int currentIndex;
  final Function(int) onIndexChanged;
  final String? initialChatId;
  final String? initialChatName;
  final String? initialChatProfileUrl;
  final bool? initialChatIsOnline;
  final Function(String chatId, String chatName, String? profileUrl, bool isOnline)? onChatSelected;

  const ChatLayoutWithMainSidebar({
    Key? key,
    this.isDesktop = false,
    required this.currentIndex,
    required this.onIndexChanged,
    this.initialChatId,
    this.initialChatName,
    this.initialChatProfileUrl,
    this.initialChatIsOnline,
    this.onChatSelected,
  }) : super(key: key);

  @override
  _ChatLayoutWithMainSidebarState createState() => _ChatLayoutWithMainSidebarState();
}

class _ChatLayoutWithMainSidebarState extends State<ChatLayoutWithMainSidebar> with TickerProviderStateMixin {
  String? _selectedChatId;
  String? _selectedChatName;
  String? _selectedUserImageUrl;
  bool _selectedUserIsOnline = false;
  bool _isMainSidebarCollapsed = false;
  late AnimationController _mainSidebarAnimationController;
  late Animation<double> _mainSidebarAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize with passed values to maintain state across layout changes
    _selectedChatId = widget.initialChatId;
    _selectedChatName = widget.initialChatName;
    _selectedUserImageUrl = widget.initialChatProfileUrl;
    _selectedUserIsOnline = widget.initialChatIsOnline ?? false;
    
    _mainSidebarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _mainSidebarAnimation = Tween<double>(
      begin: 280.0, // Full width for main sidebar
      end: 60.0,    // Collapsed width for main sidebar
    ).animate(CurvedAnimation(
      parent: _mainSidebarAnimationController,
      curve: Curves.easeInOut,
    ));
    
    // If we have a chat selected on init, collapse the sidebar
    if (_selectedChatId != null) {
      _isMainSidebarCollapsed = true;
      _mainSidebarAnimationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _mainSidebarAnimationController.dispose();
    super.dispose();
  }
  
  @override
  void didUpdateWidget(ChatLayoutWithMainSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Update state if initial values changed (e.g., window resized and widget rebuilt)
    if (widget.initialChatId != null && 
        widget.initialChatId != _selectedChatId) {
      setState(() {
        _selectedChatId = widget.initialChatId;
        _selectedChatName = widget.initialChatName;
        _selectedUserImageUrl = widget.initialChatProfileUrl;
        _selectedUserIsOnline = widget.initialChatIsOnline ?? false;
        
        // Update sidebar collapse state
        if (_selectedChatId != null && !_isMainSidebarCollapsed) {
          _isMainSidebarCollapsed = true;
          _mainSidebarAnimationController.value = 1.0;
        }
      });
    }
  }

  void _toggleMainSidebar([bool? forceCollapse]) {
    setState(() {
      if (forceCollapse != null) {
        _isMainSidebarCollapsed = forceCollapse;
      } else {
        _isMainSidebarCollapsed = !_isMainSidebarCollapsed;
      }
      
      if (_isMainSidebarCollapsed) {
        _mainSidebarAnimationController.forward();
      } else {
        _mainSidebarAnimationController.reverse();
      }
    });
  }

  void _onChatSelected(String chatId, String chatName, String? profileImageUrl, bool isOnline) {
    // Set user data immediately from the passed parameters
    setState(() {
      _selectedChatId = chatId;
      _selectedChatName = chatName;
      _selectedUserImageUrl = profileImageUrl;
      _selectedUserIsOnline = isOnline;
    });
    
    // Notify parent to persist the selection
    if (widget.onChatSelected != null) {
      widget.onChatSelected!(chatId, chatName, profileImageUrl, isOnline);
    }
    
    // Collapse main sidebar when chat is selected
    _toggleMainSidebar(true);
  }

  void _onBackToChats() {
    setState(() {
      _selectedChatId = null;
      _selectedChatName = null;
      _selectedUserImageUrl = null;
      _selectedUserIsOnline = false;
    });
    // Expand main sidebar when going back
    _toggleMainSidebar(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // Main Navigation Sidebar (collapsible)
          AnimatedBuilder(
            animation: _mainSidebarAnimation,
            builder: (context, child) {
              return Container(
                width: _mainSidebarAnimation.value,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    right: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 1,
                    ),
                  ),
                ),
                child: _isMainSidebarCollapsed 
                  ? _buildCollapsedMainSidebar()
                  : MessengerLeftSidebar(
                      currentIndex: widget.currentIndex,
                      onIndexChanged: widget.onIndexChanged,
                    ),
              );
            },
          ),
          
          // Chat List Sidebar (always visible, fixed width)
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: ChatListScreen(
              isDesktop: true,
              hideAppBar: true,
              onChatSelected: (chatId, chatName, profileImageUrl, isOnline) {
                _onChatSelected(chatId, chatName, profileImageUrl, isOnline);
              },
            ),
          ),
          
          // Center: Chat Conversation (full remaining width)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
              child: Column(
                children: [
                  // Header with toggle button
                  if (_selectedChatId != null) _buildChatHeader(),
                  // Chat content
                  Expanded(
                    child: _selectedChatId != null 
                      ? ChatScreen(
                          key: ValueKey(_selectedChatId),
                          chatId: _selectedChatId!, 
                          hideHeader: true,
                          chatPersonName: _selectedChatName,
                          chatPersonAvatarUrl: _selectedUserImageUrl,
                          chatPersonIsOnline: _selectedUserIsOnline,
                        )
                      : _buildEmptyChatView(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedMainSidebar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        children: [
          // Toggle button to expand
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _onExpandSidebar(),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.menu,
                    color: Theme.of(context).primaryColor,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 16),
          // Minimal navigation icons
          _buildMinimalNavIcon(Icons.feed, 0, 'News Feed'),
          const SizedBox(height: 8),
          _buildMinimalNavIcon(Icons.chat, 1, 'Chats'),
          const SizedBox(height: 8),
          _buildMinimalNavIcon(Icons.groups, 2, 'Stories'),
          const SizedBox(height: 8),
          _buildMinimalNavIcon(Icons.people, 3, 'Friends'),
        ],
      ),
    );
  }

  Widget _buildMinimalNavIcon(IconData icon, int index, String tooltip) {
    final isSelected = widget.currentIndex == index;
    return Container(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _onNavIconPressed(index),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected 
                ? Theme.of(context).primaryColor.withOpacity(0.2)
                : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: isSelected
                ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                : null,
            ),
            child: Icon(
              icon,
              color: isSelected 
                ? Theme.of(context).primaryColor 
                : Theme.of(context).iconTheme.color,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  void _onNavIconPressed(int index) {
    print('🚀 Navigation icon pressed: $index (current: ${widget.currentIndex})');
    
    // If navigating away from chats tab (index 1), clear selected chat and expand sidebar
    if (index != 1) {
      print('📤 Navigating away from chats - clearing chat state');
      setState(() {
        _selectedChatId = null;
      });
      // Expand main sidebar when navigating away from chats
      _toggleMainSidebar(false);
      print('📤 Sidebar expanded');
    }
    
    print('📞 Calling onIndexChanged($index)');
    // Call the navigation callback
    widget.onIndexChanged(index);
    print('✅ Navigation callback completed');
  }

  void _onExpandSidebar() {
    // Simply expand the sidebar - don't clear chat selection
    // This allows users to expand sidebar while keeping their current chat
    _toggleMainSidebar(false);
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
          // Toggle main sidebar button (only show when collapsed)
          if (_isMainSidebarCollapsed)
            IconButton(
              onPressed: () => _onExpandSidebar(),
              icon: const Icon(Icons.menu),
              tooltip: 'Show navigation',
            ),
          
          // Profile Avatar and Name
          if (_selectedChatName != null) ...[
            CircleAvatar(
              radius: 18,
              backgroundImage: (_selectedUserImageUrl != null && _selectedUserImageUrl!.isNotEmpty)
                  ? NetworkImage(_selectedUserImageUrl!)
                  : null,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
              child: (_selectedUserImageUrl == null || _selectedUserImageUrl!.isEmpty)
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _selectedChatName != null && _selectedChatName!.isNotEmpty
                            ? _selectedChatName![0].toUpperCase()
                            : 'U',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _selectedChatName!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _selectedUserIsOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: _selectedUserIsOnline 
                          ? Colors.green 
                          : Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Expanded(
              child: Center(
                child: Text(
                  'Chat',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
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