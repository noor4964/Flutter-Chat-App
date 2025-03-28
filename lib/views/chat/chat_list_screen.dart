import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:flutter/foundation.dart' show kIsWeb;

class ChatListScreen extends StatefulWidget {
  final bool isDesktop;
  final Function(String chatId, String chatName)? onChatSelected;

  const ChatListScreen({
    Key? key,
    this.isDesktop = false,
    this.onChatSelected,
  }) : super(key: key);

  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  User? user;
  StreamSubscription<QuerySnapshot>? _chatsSubscription;
  StreamSubscription<User?>? _authSubscription;
  QuerySnapshot? _lastSnapshot; // Holds the most recent data
  String? _selectedChatId;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Animation controller for new chats
  late AnimationController _animationController;

  // Scroll controller for web scrolling
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Listen to authentication state changes
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? currentUser) {
      setState(() {
        user = currentUser;
        // Refresh chat list when user changes
        if (currentUser != null) {
          _fetchChatList();
        }
      });
    });
  }

  @override
  void dispose() {
    print("Disposing ChatListScreen...");
    _chatsSubscription?.cancel();
    _authSubscription?.cancel(); // Cancel auth subscription
    _searchController.dispose();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Fetch latest chat list and store it locally
  void _fetchChatList() async {
    print("Fetching chat list...");

    try {
      await _chatsSubscription?.cancel();

      // Check if user is logged in
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print("User not logged in - cannot fetch chats");
        setState(() {
          _lastSnapshot = null;
        });
        return;
      }

      // Check if running on Windows with Firebase disabled
      if (PlatformHelper.isWindows &&
          !FirebaseConfig.isFirebaseEnabledOnWindows) {
        print("Windows detected with Firebase disabled - using mock data");
        setState(() {
          _lastSnapshot = null;
        });
        return;
      }

      _chatsSubscription = FirebaseFirestore.instance
          .collection('chats')
          .where('userIds',
              arrayContains: currentUser.uid) // Using safely stored currentUser
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
        print("Chat list fetched: ${snapshot.docs.length} documents");
        setState(() {
          _lastSnapshot = snapshot; // Save latest snapshot
          // Play animation for new items
          _animationController.reset();
          _animationController.forward();
        });
      }, onError: (error) {
        print("Error fetching chat list: $error");
        // Handle unsupported operations error
        if (error.toString().contains('Unsupported operation')) {
          print("Unsupported operation detected - using mock data");
          setState(() {
            _lastSnapshot = null;
          });
        }
      });
    } catch (e) {
      print("Error in _fetchChatList: $e");
      // Handle any other errors
      setState(() {
        _lastSnapshot = null;
      });
    }
  }

  // Fetch chat partner's name and profile picture URL
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

    if (otherUserId == "Unknown")
      return {"name": "Unknown", "profileImageUrl": ""};

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
    print("Dependencies changed, registering observer for navigation...");

    // Only register navigation observer if not in desktop mode
    if (!widget.isDesktop) {
      try {
        // Register callback with NavigatorObserver
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
                _fetchChatList(); // 🔄 Refresh chat list on return
              });
            }
          });
          print("✅ Navigation observer registered successfully");
        } else {
          print(
              "⚠️ Warning: MyNavigatorObserver not found in navigator observers");
        }
      } catch (e) {
        print("❌ Error registering navigator observer: $e");
      }
    }
  }

  Future<void> signOutUser() async {
    print("⚠️ Starting sign-out process...");
    try {
      // Show confirmation dialog
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

      // Cancel any active subscriptions first
      await _chatsSubscription?.cancel();

      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();
      print("✅ User signed out successfully");

      // No need to navigate - AuthenticationWrapper will detect the auth state change
      // and automatically show the login screen
      print(
          "🔄 Auth state will change and routing should happen automatically");
    } catch (e) {
      print("❌ Error during sign out: $e");
      // Only use manual navigation as fallback if there's an error
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

  // Filter chats based on search query
  List<DocumentSnapshot> _getFilteredChats() {
    if (_lastSnapshot == null || _searchQuery.isEmpty) {
      return _lastSnapshot?.docs ?? [];
    }

    return _lastSnapshot!.docs.where((doc) {
      var data = doc.data() as Map<String, dynamic>;
      String lastMessage = data['lastMessage'] ?? '';

      // We'll do a simple client-side filtering here
      // For a real app, you might want to use a server-side search index
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
        // Handle connection states
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Get user from stream
        final User? currentUser = snapshot.data;

        // Update the local user variable to match stream
        user = currentUser;

        if (currentUser == null) {
          // If not authenticated, show login prompt with improved UI
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

        // If user is authenticated, show the chat list UI with improved design
        final filteredChats = _getFilteredChats();

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.isDesktop ? 'Conversations' : 'Chats',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            elevation: 2,
            actions: [
              // Menu button to show actions in a popup menu
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
                            builder: (context) => PendingRequestsScreen()),
                      ).then((_) => _fetchChatList());
                      break;
                    case 'help':
                      // Handle help and feedback
                      break;
                    case 'signout':
                      signOutUser();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  // Profile List Tile
                  PopupMenuItem<String>(
                    value: 'profile',
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.person),
                      ),
                      title: const Text('Profile'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),

                  // Settings List Tile
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.settings),
                      ),
                      title: const Text('Settings'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),

                  // Add Contact List Tile
                  PopupMenuItem<String>(
                    value: 'add_contact',
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.person_add),
                      ),
                      title: const Text('Add New Contact'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),

                  // Pending Requests List Tile
                  PopupMenuItem<String>(
                    value: 'requests',
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.3),
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

                  // Help & Feedback List Tile
                  PopupMenuItem<String>(
                    value: 'help',
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.help_outline),
                      ),
                      title: const Text('Help & Feedback'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),

                  // Sign Out List Tile (only shown in non-desktop mode)
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
                          child: const Icon(Icons.logout, color: Colors.red),
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
              // Search bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search conversations...',
                    prefixIcon: const Icon(Icons.search),
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
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),

              // Chat list
              Expanded(
                child: _lastSnapshot == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Loading conversations...',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : filteredChats.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchQuery.isEmpty
                                      ? Icons.chat_bubble_outline
                                      : Icons.search_off,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'No conversations yet'
                                      : 'No conversations matching "$_searchQuery"',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                if (_searchQuery.isEmpty) ...[
                                  const SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Start a new chat'),
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
                            // Configure scrolling behavior for web
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
                              dragStartBehavior:
                                  DragStartBehavior.down, // Enhances scrolling
                              padding: const EdgeInsets.only(
                                  bottom: 80), // Add padding for FAB
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

                                    // Safely access user UID to check if message is read
                                    bool isRead = false;
                                    if (user != null &&
                                        chatData['lastMessageReadBy'] != null) {
                                      isRead = (chatData['lastMessageReadBy']
                                              as List<dynamic>)
                                          .contains(user!.uid);
                                    }

                                    bool isSelected = widget.isDesktop &&
                                        chatId == _selectedChatId;

                                    // Get formatted time
                                    String timeString = '';
                                    if (chatData['createdAt'] != null) {
                                      final timestamp =
                                          (chatData['createdAt'] as Timestamp);
                                      final now = DateTime.now();
                                      final messageDate = timestamp.toDate();

                                      if (now.difference(messageDate).inDays ==
                                          0) {
                                        // Today - show time
                                        timeString =
                                            '${messageDate.hour}:${messageDate.minute.toString().padLeft(2, '0')}';
                                      } else if (now
                                              .difference(messageDate)
                                              .inDays <
                                          7) {
                                        // Within a week - show day name
                                        final days = [
                                          'Mon',
                                          'Tue',
                                          'Wed',
                                          'Thu',
                                          'Fri',
                                          'Sat',
                                          'Sun'
                                        ];
                                        timeString =
                                            days[messageDate.weekday - 1];
                                      } else {
                                        // Older - show date
                                        timeString =
                                            '${messageDate.day}/${messageDate.month}';
                                      }
                                    }

                                    return SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(-0.2, 0),
                                        end: Offset.zero,
                                      ).animate(CurvedAnimation(
                                        parent: _animationController,
                                        curve: Curves.easeOut,
                                      )),
                                      child: Card(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        elevation: isSelected ? 4 : 1,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          side: isSelected
                                              ? BorderSide(
                                                  color: colorScheme.primary,
                                                  width: 1.5)
                                              : BorderSide.none,
                                        ),
                                        color: isSelected
                                            ? colorScheme.primaryContainer
                                                .withOpacity(0.2)
                                            : null,
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: () async {
                                            if (widget.isDesktop &&
                                                widget.onChatSelected != null) {
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
                                            padding: const EdgeInsets.all(8.0),
                                            child: Row(
                                              children: [
                                                Stack(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              2),
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        border: isSelected
                                                            ? Border.all(
                                                                color:
                                                                    colorScheme
                                                                        .primary,
                                                                width: 2,
                                                              )
                                                            : null,
                                                      ),
                                                      child: CircleAvatar(
                                                        radius: 24,
                                                        backgroundImage:
                                                            profileImageUrl
                                                                    .isNotEmpty
                                                                ? NetworkImage(
                                                                    profileImageUrl)
                                                                : null,
                                                        backgroundColor:
                                                            colorScheme.primary
                                                                .withOpacity(
                                                                    0.2),
                                                        child:
                                                            profileImageUrl
                                                                    .isEmpty
                                                                ? Text(
                                                                    chatName.isNotEmpty
                                                                        ? chatName[0]
                                                                            .toUpperCase()
                                                                        : '?',
                                                                    style:
                                                                        TextStyle(
                                                                      color: colorScheme
                                                                          .primary,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontSize:
                                                                          18,
                                                                    ),
                                                                  )
                                                                : null,
                                                      ),
                                                    ),
                                                    // Online status indicator
                                                    // In a real app, you'd use actual online status
                                                    if (index % 3 ==
                                                        0) // Just for demonstration
                                                      Positioned(
                                                        right: 0,
                                                        bottom: 0,
                                                        child: Container(
                                                          width: 12,
                                                          height: 12,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.green,
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                              color:
                                                                  Colors.white,
                                                              width: 2,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(width: 12),
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
                                                              style: TextStyle(
                                                                fontWeight: isRead
                                                                    ? FontWeight
                                                                        .normal
                                                                    : FontWeight
                                                                        .bold,
                                                                fontSize: 16,
                                                              ),
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                          Text(
                                                            timeString,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: isRead
                                                                  ? Colors.grey
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
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              chatData[
                                                                      'lastMessage'] ??
                                                                  "Tap to open chat",
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                color: isRead
                                                                    ? Colors
                                                                        .grey
                                                                    : Colors
                                                                        .black87,
                                                              ),
                                                            ),
                                                          ),
                                                          if (!isRead)
                                                            Container(
                                                              margin:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      left: 8),
                                                              width: 8,
                                                              height: 8,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color:
                                                                    colorScheme
                                                                        .primary,
                                                                shape: BoxShape
                                                                    .circle,
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
                                    );
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserListScreen()),
              );
            },
            icon: const Icon(Icons.chat),
            label: const Text('New Chat'),
            tooltip: 'Start a new conversation',
          ),
        );
      },
    );
  }

  // Shimmer loading effect for chat items
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
}
