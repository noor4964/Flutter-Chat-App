import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // Added import for HapticFeedback
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/views/profile/profile_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';
import 'package:flutter_chat_app/views/pending_requests_screen.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'chat_screen.dart';
import 'package:flutter_chat_app/services/navigator_observer.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerDeviceKind;

class ChatListScreen extends StatefulWidget {
  final bool isDesktop;
  final Function(String chatId, String chatName)? onChatSelected;
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
    with TickerProviderStateMixin {
  User? user;
  StreamSubscription<QuerySnapshot>? _chatsSubscription;
  StreamSubscription<User?>? _authSubscription;
  QuerySnapshot? _lastSnapshot;
  String? _selectedChatId;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late AnimationController _animationController;
  late AnimationController _listAnimationController;
  final List<Animation<double>> _itemAnimations = [];
  bool _isSearchFocused = false;
  final ScrollController _scrollController = ScrollController();

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

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? currentUser) {
      setState(() {
        user = currentUser;
        if (currentUser != null) {
          _fetchChatList();
        }
      });
    });
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    _authSubscription?.cancel();
    _searchController.dispose();
    _animationController.dispose();
    _listAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeItemAnimations(int itemCount) {
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
    _listAnimationController.forward(from: 0.0);
  }

  void _fetchChatList() async {
    try {
      await _chatsSubscription?.cancel();

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _lastSnapshot = null;
        });
        return;
      }

      if (PlatformHelper.isWindows &&
          !FirebaseConfig.isFirebaseEnabledOnWindows) {
        setState(() {
          _lastSnapshot = null;
        });
        return;
      }

      try {
        _chatsSubscription = FirebaseFirestore.instance
            .collection('chats')
            .where('userIds', arrayContains: currentUser.uid)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .listen((snapshot) {
          final filteredDocs = snapshot.docs.where((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            return data['isDeleted'] != true;
          }).toList();

          if (mounted) {
            setState(() {
              _lastSnapshot = snapshot;
              _initializeItemAnimations(filteredDocs.length);
              _animationController.reset();
              _animationController.forward();
            });
          }
        }, onError: (error) {
          if (error.toString().contains('requires an index')) {
            print(
                "Index error detected. Please deploy the index configured in firestore.indexes.json");
          }

          if (error.toString().contains('Unsupported operation')) {
            setState(() {
              _lastSnapshot = null;
            });
          }
        });
      } catch (e) {
        setState(() {
          _lastSnapshot = null;
        });
      }
    } catch (e) {
      setState(() {
        _lastSnapshot = null;
      });
    }
  }

  Future<Map<String, String>> fetchChatPartnerInfo(List<String> userIds) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return {"name": "Not logged in", "profileImageUrl": ""};
    }

    String currentUserId = currentUser.uid;
    String otherUserId = userIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => "Unknown",
    );

    if (otherUserId == "Unknown") {
      return {"name": "Unknown", "profileImageUrl": ""};
    }

    try {
      var userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(otherUserId)
          .get();
      if (userDoc.exists) {
        return {
          "name": userDoc.data()?['username'] ?? 'Unknown',
          "profileImageUrl": userDoc.data()?['profileImageUrl'] ?? ''
        };
      }
    } catch (e) {
      debugPrint("Error fetching user: $e");
    }
    return {"name": "Unknown", "profileImageUrl": ""};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!widget.isDesktop) {
      try {
        final navigatorObservers = Navigator.of(context).widget.observers;
        MyNavigatorObserver? observer;

        for (var obs in navigatorObservers) {
          if (obs is MyNavigatorObserver) {
            observer = obs;
            break;
          }
        }

        if (observer != null) {
          observer.setCallback(() {
            if (mounted) {
              setState(() {
                _fetchChatList();
              });
            }
          });
        }
      } catch (e) {
        print("Error registering navigator observer: $e");
      }
    }
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

      await _chatsSubscription?.cancel();
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

  List<DocumentSnapshot> _getFilteredChats() {
    if (_lastSnapshot == null || _searchQuery.isEmpty) {
      return _lastSnapshot?.docs ?? [];
    }

    return _lastSnapshot!.docs.where((doc) {
      var data = doc.data() as Map<String, dynamic>;
      String lastMessage = data['lastMessage'] ?? '';
      return lastMessage.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final User? currentUser = snapshot.data;
        user = currentUser;

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

        final filteredChats = _getFilteredChats();

        return Scaffold(
          appBar: widget.hideAppBar
              ? null
              : AppBar(
                  title: Text(
                    widget.isDesktop ? 'Conversations' : 'Chats',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  elevation: 2,
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
                            ).then((_) => _fetchChatList());
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: _isSearchFocused ? 12.0 : 16.0,
                ),
                decoration: BoxDecoration(
                  color: _isSearchFocused
                      ? colorScheme.primaryContainer.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search conversations...',
                    prefixIcon: Icon(
                      Icons.search,
                      color: _isSearchFocused ? colorScheme.primary : Colors.grey,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.withOpacity(0.1),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide:
                          BorderSide(color: colorScheme.primary, width: 1),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
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
                child: _lastSnapshot == null
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

                                return FutureBuilder<Map<String, String>>(
                                  future: fetchChatPartnerInfo(userIds),
                                  builder: (context, infoSnapshot) {
                                    if (infoSnapshot.hasError) {
                                      return const ListTile(
                                          title: Text("Error loading info"));
                                    }
                                    if (!infoSnapshot.hasData) {
                                      return _buildChatShimmer();
                                    }

                                    String chatName =
                                        infoSnapshot.data!["name"]!;
                                    String profileImageUrl =
                                        infoSnapshot.data!["profileImageUrl"]!;

                                    bool isRead = false;
                                    if (user != null &&
                                        chatData['lastMessageReadBy'] != null) {
                                      isRead = (chatData['lastMessageReadBy']
                                              as List<dynamic>)
                                          .contains(user!.uid);
                                    }

                                    bool isSelected = widget.isDesktop &&
                                        chatId == _selectedChatId;

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
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        alignment: Alignment.centerRight,
                                        padding:
                                            const EdgeInsets.only(right: 20.0),
                                        child: const Icon(
                                          Icons.delete,
                                          color: Colors.white,
                                        ),
                                      ),
                                      direction: DismissDirection.endToStart,
                                      confirmDismiss: (direction) async {
                                        return await showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text(
                                                'Delete Conversation'),
                                            content: Text(
                                                'Are you sure you want to delete your conversation with $chatName?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(true),
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
                                        opacity: _itemAnimations.isNotEmpty &&
                                                index < _itemAnimations.length
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
                                          child: Card(
                                            margin: const EdgeInsets.symmetric(
                                                vertical: 4, horizontal: 8),
                                            elevation: isSelected ? 4 : 1,
                                            shadowColor: isSelected
                                                ? colorScheme.primary
                                                    .withOpacity(0.3)
                                                : Colors.black.withOpacity(0.1),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              side: isSelected
                                                  ? BorderSide(
                                                      color:
                                                          colorScheme.primary,
                                                      width: 1.5)
                                                  : BorderSide.none,
                                            ),
                                            color: isSelected
                                                ? colorScheme.primaryContainer
                                                    .withOpacity(0.2)
                                                : Colors.white,
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              splashColor: colorScheme.primary
                                                  .withOpacity(0.1),
                                              highlightColor: colorScheme
                                                  .primary
                                                  .withOpacity(0.05),
                                              onTap: () async {
                                                HapticFeedback.lightImpact();

                                                if (widget.isDesktop &&
                                                    widget.onChatSelected !=
                                                        null) {
                                                  setState(() {
                                                    _selectedChatId = chatId;
                                                  });
                                                  widget.onChatSelected!(
                                                      chatId, chatName);
                                                } else {
                                                  bool? shouldRefresh =
                                                      await Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          ChatScreen(
                                                              chatId: chatId),
                                                    ),
                                                  );
                                                  if (shouldRefresh == true) {
                                                    _fetchChatList();
                                                  }
                                                }
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12.0,
                                                        vertical: 10.0),
                                                child: Row(
                                                  children: [
                                                    Stack(
                                                      children: [
                                                        Hero(
                                                          tag: 'avatar_$chatId',
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(2),
                                                            decoration:
                                                                BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              border: isSelected
                                                                  ? Border.all(
                                                                      color: colorScheme
                                                                          .primary,
                                                                      width: 2,
                                                                    )
                                                                  : !isRead
                                                                      ? Border
                                                                          .all(
                                                                          color:
                                                                              colorScheme.primary,
                                                                          width:
                                                                              1.5,
                                                                        )
                                                                      : null,
                                                              boxShadow: isSelected ||
                                                                      !isRead
                                                                  ? [
                                                                      BoxShadow(
                                                                        color: colorScheme
                                                                            .primary
                                                                            .withOpacity(0.3),
                                                                        blurRadius:
                                                                            8,
                                                                        spreadRadius:
                                                                            1,
                                                                      )
                                                                    ]
                                                                  : null,
                                                            ),
                                                            child: CircleAvatar(
                                                              radius:
                                                                  26, // Slightly larger avatar
                                                              backgroundImage:
                                                                  profileImageUrl
                                                                          .isNotEmpty
                                                                      ? NetworkImage(
                                                                          profileImageUrl)
                                                                      : null,
                                                              backgroundColor:
                                                                  colorScheme
                                                                      .primary
                                                                      .withOpacity(
                                                                          0.2),
                                                              child: profileImageUrl
                                                                      .isEmpty
                                                                  ? Text(
                                                                      chatName.isNotEmpty
                                                                          ? chatName[
                                                                                  0]
                                                                              .toUpperCase()
                                                                          : '?',
                                                                      style:
                                                                          TextStyle(
                                                                        color: colorScheme
                                                                            .primary,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontSize:
                                                                            20,
                                                                      ),
                                                                    )
                                                                  : null,
                                                            ),
                                                          ),
                                                        ),
                                                        if (index % 3 == 0)
                                                          Positioned(
                                                            right: 2,
                                                            bottom: 2,
                                                            child: Container(
                                                              width: 14,
                                                              height: 14,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .green,
                                                                shape: BoxShape
                                                                    .circle,
                                                                border:
                                                                    Border.all(
                                                                  color: Colors
                                                                      .white,
                                                                  width: 2,
                                                                ),
                                                                boxShadow: [
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .black
                                                                        .withOpacity(
                                                                            0.2),
                                                                    blurRadius:
                                                                        2,
                                                                    spreadRadius:
                                                                        0,
                                                                  )
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(width: 14),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .spaceBetween,
                                                            children: [
                                                              Flexible(
                                                                child: Text(
                                                                  chatName,
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight: isRead
                                                                        ? FontWeight
                                                                            .normal
                                                                        : FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        16,
                                                                    color: isRead
                                                                        ? Colors
                                                                            .black87
                                                                        : colorScheme
                                                                            .primary,
                                                                  ),
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                              Row(
                                                                children: [
                                                                  if (!isRead)
                                                                    Container(
                                                                      margin: const EdgeInsets
                                                                              .only(
                                                                          right:
                                                                              6),
                                                                      padding: const EdgeInsets
                                                                              .symmetric(
                                                                          horizontal:
                                                                              8,
                                                                          vertical:
                                                                              2),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: colorScheme
                                                                            .primary,
                                                                        borderRadius:
                                                                            BorderRadius.circular(10),
                                                                      ),
                                                                      child:
                                                                          const Text(
                                                                        'NEW',
                                                                        style:
                                                                            TextStyle(
                                                                          color:
                                                                              Colors.white,
                                                                          fontSize:
                                                                              10,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  Text(
                                                                    timeString,
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      color: isRead
                                                                          ? Colors
                                                                              .grey
                                                                          : colorScheme
                                                                              .primary,
                                                                      fontWeight: isRead
                                                                          ? FontWeight
                                                                              .normal
                                                                          : FontWeight
                                                                              .bold,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                              height: 6),
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(
                                                                  chatData[
                                                                          'lastMessage'] ??
                                                                      "Tap to start chatting",
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        14,
                                                                    color: isRead
                                                                        ? Colors
                                                                            .grey[600]
                                                                        : Colors
                                                                            .black87,
                                                                  ),
                                                                ),
                                                              ),
                                                              if (!isRead)
                                                                AnimatedContainer(
                                                                  duration: const Duration(
                                                                      milliseconds:
                                                                          300),
                                                                  margin: const EdgeInsets
                                                                      .only(
                                                                      left: 8),
                                                                  width: 10,
                                                                  height: 10,
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: colorScheme
                                                                        .primary,
                                                                    shape: BoxShape
                                                                        .circle,
                                                                    boxShadow: [
                                                                      BoxShadow(
                                                                        color: colorScheme
                                                                            .primary
                                                                            .withOpacity(0.4),
                                                                        blurRadius:
                                                                            4,
                                                                        spreadRadius:
                                                                            1,
                                                                      )
                                                                    ],
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
          floatingActionButton: _searchQuery.isEmpty
              ? FloatingActionButton.extended(
                  onPressed: () {
                    HapticFeedback.mediumImpact();

                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => UserListScreen()),
                    );
                  },
                  icon: const Icon(Icons.chat),
                  label: const Text('New Chat'),
                  tooltip: 'Start a new conversation',
                  elevation: 4,
                  highlightElevation: 8,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: Colors.white,
                )
              : null,
        );
      },
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

      _fetchChatList();

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
