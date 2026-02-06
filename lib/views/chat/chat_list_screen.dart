import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/chat_provider.dart';
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/views/profile/profile_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';
import 'package:flutter_chat_app/views/pending_requests_screen.dart';
import 'chat_screen.dart';
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerDeviceKind;

class ChatListScreen extends StatefulWidget {
  final bool isDesktop;
  final Function(String chatId, String chatName, String? profileImageUrl, bool isOnline)? onChatSelected;
  final bool hideAppBar;

  const ChatListScreen({
    Key? key,
    this.isDesktop = false,
    this.onChatSelected,
    this.hideAppBar = false,
  }) : super(key: key);

  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  String? _selectedChatId;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late AnimationController _animationController;
  late AnimationController _listAnimationController;
  final List<Animation<double>> _itemAnimations = [];
  bool _isSearchFocused = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebouncer;
  bool _hasPlayedInitialAnimation = false;
  int _lastAnimatedCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _listAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    _listAnimationController.dispose();
    _scrollController.dispose();
    _searchDebouncer?.cancel();
    super.dispose();
  }

  void _initializeItemAnimations(int itemCount) {
    // Only replay animation on first load, not on every data update
    if (_hasPlayedInitialAnimation && itemCount <= _lastAnimatedCount) return;

    _itemAnimations.clear();
    for (int i = 0; i < itemCount; i++) {
      final start = i * 0.05;
      _itemAnimations.add(
        CurvedAnimation(
          parent: _listAnimationController,
          curve: Interval(
            start.clamp(0.0, 0.9),
            (start + 0.5).clamp(0.0, 1.0),
            curve: Curves.easeOutQuart,
          ),
        ),
      );
    }
    _lastAnimatedCount = itemCount;
    _hasPlayedInitialAnimation = true;
    _listAnimationController.forward(from: 0.0);
    _animationController.forward(from: 0.0);
  }



  Future<void> signOutUser() async {
    try {
      bool confirm = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Sign Out'),
              content: const Text('Are you sure you want to sign out?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirm) return;

      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out error: $e')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebouncer?.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = value;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUser = FirebaseAuth.instance.currentUser;

    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {

        // Run item animation when chat list count changes
        final chatDocs = chatProvider.getFilteredChats(_searchQuery);
        if (chatDocs.isNotEmpty) {
          // Schedule animation after build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _initializeItemAnimations(chatDocs.length);
          });
        }

        if (currentUser == null) {
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colorScheme.primary.withOpacity(0.8),
                    colorScheme.primary.withOpacity(0.4),
                  ],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.all(16),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 72, color: colorScheme.primary),
                          const SizedBox(height: 24),
                          const Text(
                            'Welcome to Flutter Chat',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Please sign in to continue',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.login),
                            label: const Text('Sign In'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 32, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => LoginScreen()),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final filteredChats = chatDocs;

        return Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? colorScheme.surface
              : const Color(0xFFFAFAFA),
          appBar: widget.hideAppBar
              ? null
              : AppBar(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? colorScheme.surface
                      : Colors.white,
                  elevation: 0,
                  scrolledUnderElevation: 0.5,
                  surfaceTintColor: Colors.transparent,
                  title: Text(
                    widget.isDesktop ? 'Conversations' : 'Chats',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  actions: [
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      tooltip: 'Menu',
                      onSelected: (value) {
                        switch (value) {
                          case 'profile':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ProfileScreen()),
                            );
                            break;
                          case 'settings':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => SettingsScreen()),
                            );
                            break;
                          case 'add_contact':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => UserListScreen()),
                            );
                            break;
                          case 'requests':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      PendingRequestsScreen()),
                            );
                            break;
                          case 'help':
                            break;
                          case 'signout':
                            signOutUser();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'profile',
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.person),
                            ),
                            title: const Text('Profile'),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'settings',
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.settings),
                            ),
                            title: const Text('Settings'),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'add_contact',
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.person_add),
                            ),
                            title: const Text('Add New Contact'),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'requests',
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(Icons.notifications),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(1),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 8,
                                        minHeight: 8,
                                      ),
                                      child: const Text(''),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            title: const Text('Pending Requests'),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'help',
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.help_outline),
                            ),
                            title: const Text('Help & Feedback'),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        if (!widget.isDesktop)
                          PopupMenuItem<String>(
                            value: 'signout',
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child:
                                    const Icon(Icons.logout, color: Colors.red),
                              ),
                              title: const Text(
                                'Sign Out',
                                style: TextStyle(color: Colors.red),
                              ),
                              dense: true,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
          drawer: !widget.isDesktop
              ? Drawer(
                  child: Column(
                    children: <Widget>[
                      UserAccountsDrawerHeader(
                        accountName:
                            Text(currentUser.displayName ?? 'Chat User'),
                        accountEmail: Text(currentUser.email ?? ''),
                        currentAccountPicture: CircleAvatar(
                          backgroundImage: currentUser.photoURL != null
                              ? NetworkImage(currentUser.photoURL!)
                              : null,
                          child: currentUser.photoURL == null
                              ? Text(
                                  (currentUser.displayName?.isNotEmpty ?? false)
                                      ? currentUser.displayName![0]
                                          .toUpperCase()
                                      : (currentUser.email?.isNotEmpty ?? false)
                                          ? currentUser.email![0].toUpperCase()
                                          : '?',
                                  style: const TextStyle(fontSize: 24),
                                )
                              : null,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: <Widget>[
                            ListTile(
                              leading: const Icon(Icons.chat),
                              title: const Text('Chats'),
                              selected: true,
                              selectedTileColor:
                                  colorScheme.primaryContainer.withOpacity(0.3),
                              onTap: () {
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                )
              : null,
          body: Column(
            children: [
              // Search bar with improved styling
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? colorScheme.surface
                      : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search conversations...',
                    hintStyle: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.4),
                      fontSize: 15,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: _isSearchFocused
                          ? colorScheme.primary
                          : colorScheme.onSurface.withOpacity(0.4),
                      size: 22,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: colorScheme.onSurface.withOpacity(0.5),
                              size: 20,
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? colorScheme.surfaceContainerHighest.withOpacity(0.3)
                        : Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.5), width: 1.5),
                    ),
                  ),
                  onChanged: (value) {
                    _onSearchChanged(value);
                  },
                  onTap: () {
                    setState(() {
                      _isSearchFocused = true;
                    });
                  },
                  onEditingComplete: () {
                    setState(() {
                      _isSearchFocused = false;
                      FocusScope.of(context).unfocus();
                    });
                  },
                ),
              ),
              Expanded(
                child: chatProvider.isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 120,
                              height: 120,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Loading your conversations...',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : filteredChats.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer
                                        .withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _searchQuery.isEmpty
                                        ? Icons.chat_bubble_outline
                                        : Icons.search_off,
                                    size: 80,
                                    color: colorScheme.primary.withOpacity(0.8),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'No conversations yet'
                                      : 'No conversations matching "$_searchQuery"',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'Start a new chat to connect with friends'
                                      : 'Try a different search term',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                ),
                                if (_searchQuery.isEmpty) ...[
                                  const SizedBox(height: 32),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Start a new chat'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      elevation: 4,
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                UserListScreen()),
                                      );
                                    },
                                  ),
                                ]
                              ],
                            ),
                          )
                        : ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                                PointerDeviceKind.trackpad,
                              },
                              physics: const BouncingScrollPhysics(),
                            ),
                            child: ListView.builder(
                              controller: _scrollController,
                              itemCount: filteredChats.length,
                              dragStartBehavior: DragStartBehavior.down,
                              padding: const EdgeInsets.only(bottom: 80),
                              itemBuilder: (context, index) {
                                var chatData = filteredChats[index].data()
                                    as Map<String, dynamic>;
                                String chatId = filteredChats[index].id;
                                List<String> userIds = List<String>.from(
                                    chatData['userIds'] ?? []);

                                return _buildChatListItem(
                                  chatData: chatData,
                                  chatId: chatId,
                                  userIds: userIds,
                                  index: index,
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
          floatingActionButton: _searchQuery.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: FloatingActionButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => UserListScreen()),
                      );
                    },
                    tooltip: 'Start a new conversation',
                    elevation: 0,
                    backgroundColor: colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.edit_rounded, color: Colors.white),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildChatListItem({
    required Map<String, dynamic> chatData,
    required String chatId,
    required List<String> userIds,
    required int index,
  }) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return _buildChatShimmer();
    }

    final otherUserId = userIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );

    // Get user info from provider cache or show shimmer while loading
    final chatProvider = context.read<ChatProvider>();
    Map<String, String>? userInfo;
    if (otherUserId.isNotEmpty) {
      userInfo = chatProvider.getCachedUserInfo(otherUserId);
    }

    if (userInfo == null) {
      // Start loading user info if not in cache
      if (otherUserId.isNotEmpty) {
        chatProvider.fetchUserInfo(otherUserId);
      }
      return _buildChatShimmer();
    }

    final chatName = userInfo['name'] ?? 'Unknown';
    final profileImageUrl = userInfo['profileImageUrl'] ?? '';
    
    bool isRead = false;
    if (chatData['lastMessageReadBy'] != null) {
      isRead = (chatData['lastMessageReadBy'] as List<dynamic>)
          .contains(currentUserId);
    }

    bool isSelected = widget.isDesktop && chatId == _selectedChatId;

    // Format timestamp for display
    String timeString = 'Just now';
    if (chatData['lastMessageTimestamp'] != null) {
      final timestamp = (chatData['lastMessageTimestamp'] as Timestamp).toDate();
      final now = DateTime.now();
      final difference = now.difference(timestamp);
      
      if (difference.inDays > 365) {
        timeString = '${(difference.inDays / 365).floor()}y';
      } else if (difference.inDays > 30) {
        timeString = '${(difference.inDays / 30).floor()}mo';
      } else if (difference.inDays > 0) {
        timeString = '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        timeString = '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        timeString = '${difference.inMinutes}m';
      }
    }

    return Dismissible(
      key: ValueKey(chatId),
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Conversation'),
            content: Text(
                'Are you sure you want to delete your conversation with $chatName?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        _deleteChat(chatId, chatName);
      },
      child: FadeTransition(
        opacity: _itemAnimations.isNotEmpty && index < _itemAnimations.length
            ? _itemAnimations[index]
            : const AlwaysStoppedAnimation(1.0),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.2, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          )),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                      width: 1.5,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                      : Colors.black.withOpacity(0.04),
                  blurRadius: isSelected ? 12 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                splashColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                highlightColor: Theme.of(context).colorScheme.primary.withOpacity(0.04),
                onTap: () {
                  HapticFeedback.lightImpact();

                  if (widget.isDesktop) {
                    setState(() {
                      _selectedChatId = chatId;
                    });

                    if (widget.onChatSelected != null) {
                      widget.onChatSelected!(
                        chatId,
                        chatName,
                        profileImageUrl.isNotEmpty ? profileImageUrl : null,
                        false,
                      );
                    }
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          chatId: chatId,
                          chatPersonName: chatName,
                          chatPersonAvatarUrl: profileImageUrl.isNotEmpty ? profileImageUrl : null,
                        ),
                      ),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // Avatar with subtle background
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                        ),
                        child: CircleAvatar(
                          radius: 26,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.6),
                          backgroundImage: profileImageUrl.isNotEmpty
                              ? NetworkImage(profileImageUrl)
                              : null,
                          child: profileImageUrl.isEmpty
                              ? Text(
                                  chatName.isNotEmpty ? chatName[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Name + message
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chatName,
                              style: TextStyle(
                                fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                                fontSize: 15.5,
                                letterSpacing: 0.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              chatData['lastMessage'] ?? 'No messages yet',
                              style: TextStyle(
                                color: isRead
                                    ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                fontWeight: isRead ? FontWeight.w400 : FontWeight.w500,
                                fontSize: 13.5,
                                height: 1.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Time + unread dot
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeString,
                            style: TextStyle(
                              color: !isRead
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                              fontSize: 12,
                              fontWeight: !isRead ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          if (!isRead) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.primary.withOpacity(0.7),
                                  ],
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 100,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChat(String chatId, String chatName) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleting conversation...')),
        );
      }

      final messagesQuery = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (var doc in messagesQuery.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(FirebaseFirestore.instance.collection('chats').doc(chatId));

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conversation with $chatName deleted'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (widget.isDesktop && chatId == _selectedChatId) {
        setState(() {
          _selectedChatId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting conversation: $e')),
        );
      }
    }
  }
}

class _CustomDocumentSnapshot {
  final String _id;
  final Map<String, dynamic> _data;

  _CustomDocumentSnapshot(this._id, this._data);

  String get id => _id;
  Map<String, dynamic> data() => _data;
  dynamic get(Object field) => _data[field];
  bool get exists => true;
  DocumentReference<Object?> get reference =>
      FirebaseFirestore.instance.collection('chats').doc(_id);
  SnapshotMetadata get metadata => _CustomSnapshotMetadata(
        hasPendingWrites: false,
        isFromCache: false,
      );
  dynamic operator [](Object field) => _data[field];
  bool containsKey(Object field) => _data.containsKey(field);
  String get documentID => _id;
}

class _CustomQuerySnapshot {
  final List<_CustomDocumentSnapshot> _docs;

  _CustomQuerySnapshot(this._docs);

  List<_CustomDocumentSnapshot> get docs => _docs;
  List<DocumentChange<Object?>> get docChanges => [];
  SnapshotMetadata get metadata => _CustomSnapshotMetadata(
        hasPendingWrites: false,
        isFromCache: false,
      );
  int get size => _docs.length;
  bool get isEmpty => _docs.isEmpty;
  List<_CustomDocumentSnapshot> get documents => _docs;
}

class _CustomSnapshotMetadata implements SnapshotMetadata {
  final bool _hasPendingWrites;
  final bool _isFromCache;

  const _CustomSnapshotMetadata({
    required bool hasPendingWrites,
    required bool isFromCache,
  })  : _hasPendingWrites = hasPendingWrites,
        _isFromCache = isFromCache;

  @override
  bool get hasPendingWrites => _hasPendingWrites;

  @override
  bool get isFromCache => _isFromCache;
}
