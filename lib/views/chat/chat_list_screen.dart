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
  
  // Performance optimizations
  final Map<String, Map<String, String>> _userInfoCache = {};
  final Map<String, Future<Map<String, String>>> _pendingUserFetches = {};
  List<DocumentSnapshot> _cachedFilteredChats = [];
  String _lastSearchQuery = '';
  Timer? _searchDebouncer;

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
    _searchDebouncer?.cancel();
    _userInfoCache.clear();
    _pendingUserFetches.clear();
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
            .listen((snapshot) async {
          final filteredDocs = snapshot.docs.where((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            return data['isDeleted'] != true;
          }).toList();

          // Pre-fetch user info for all chats in batch
          _prefetchUserInfo(filteredDocs);

          if (mounted) {
            setState(() {
              _lastSnapshot = snapshot;
              _cachedFilteredChats.clear(); // Clear cache when data changes
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

    // Check cache first
    if (_userInfoCache.containsKey(otherUserId)) {
      return _userInfoCache[otherUserId]!;
    }

    // Check if we're already fetching this user
    if (_pendingUserFetches.containsKey(otherUserId)) {
      return _pendingUserFetches[otherUserId]!;
    }

    // Create the fetch future and cache it
    final fetchFuture = _fetchUserInfo(otherUserId);
    _pendingUserFetches[otherUserId] = fetchFuture;

    try {
      final result = await fetchFuture;
      _userInfoCache[otherUserId] = result;
      _pendingUserFetches.remove(otherUserId);
      return result;
    } catch (e) {
      _pendingUserFetches.remove(otherUserId);
      rethrow;
    }
  }

  Future<Map<String, String>> _fetchUserInfo(String userId) async {
    try {
      var userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
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

  // Batch fetch multiple users at once for better performance
  Future<Map<String, Map<String, String>>> batchFetchUsers(Set<String> userIds) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return {};

    // Filter out current user and already cached users
    final uncachedUserIds = userIds
        .where((id) => id != currentUser.uid && !_userInfoCache.containsKey(id))
        .toList();

    if (uncachedUserIds.isEmpty) {
      // Return cached results
      final result = <String, Map<String, String>>{};
      for (final id in userIds) {
        if (id != currentUser.uid && _userInfoCache.containsKey(id)) {
          result[id] = _userInfoCache[id]!;
        }
      }
      return result;
    }

    try {
      // Batch fetch users in chunks to avoid large queries
      const chunkSize = 10;
      final results = <String, Map<String, String>>{};

      for (int i = 0; i < uncachedUserIds.length; i += chunkSize) {
        final chunk = uncachedUserIds.skip(i).take(chunkSize).toList();
        
        final querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in querySnapshot.docs) {
          final userInfo = {
            "name": (doc.data()['username'] ?? 'Unknown') as String,
            "profileImageUrl": (doc.data()['profileImageUrl'] ?? '') as String
          };
          results[doc.id] = userInfo;
          _userInfoCache[doc.id] = userInfo;
        }

        // Handle users not found in the query
        for (final userId in chunk) {
          if (!results.containsKey(userId)) {
            final defaultInfo = {"name": "Unknown", "profileImageUrl": ""};
            results[userId] = defaultInfo;
            _userInfoCache[userId] = defaultInfo;
          }
        }
      }

      // Add already cached results
      for (final id in userIds) {
        if (id != currentUser.uid && _userInfoCache.containsKey(id) && !results.containsKey(id)) {
          results[id] = _userInfoCache[id]!;
        }
      }

      return results;
    } catch (e) {
      debugPrint("Error batch fetching users: $e");
      return {};
    }
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
    if (_lastSnapshot == null) return [];

    // Use cached results if search query hasn't changed
    if (_searchQuery == _lastSearchQuery && _cachedFilteredChats.isNotEmpty) {
      return _cachedFilteredChats;
    }

    List<DocumentSnapshot> filtered;
    if (_searchQuery.isEmpty) {
      filtered = _lastSnapshot!.docs.where((doc) {
        var data = doc.data() as Map<String, dynamic>;
        return data['isDeleted'] != true;
      }).toList();
    } else {
      final query = _searchQuery.toLowerCase();
      filtered = _lastSnapshot!.docs.where((doc) {
        var data = doc.data() as Map<String, dynamic>;
        if (data['isDeleted'] == true) return false;
        
        String lastMessage = (data['lastMessage'] ?? '').toString().toLowerCase();
        
        // Also search in cached user names
        final userIds = List<String>.from(data['userIds'] ?? []);
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final otherUserId = userIds.firstWhere(
          (id) => id != currentUserId,
          orElse: () => '',
        );
        
        String userName = '';
        if (otherUserId.isNotEmpty && _userInfoCache.containsKey(otherUserId)) {
          userName = _userInfoCache[otherUserId]!['name']?.toLowerCase() ?? '';
        }
        
        return lastMessage.contains(query) || userName.contains(query);
      }).toList();
    }

    // Cache the results
    _cachedFilteredChats = filtered;
    _lastSearchQuery = _searchQuery;
    
    return filtered;
  }

  void _onSearchChanged(String value) {
    _searchDebouncer?.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = value;
          _cachedFilteredChats.clear(); // Clear cache when search changes
        });
      }
    });
  }

  // Pre-fetch user information for all chats to improve performance
  void _prefetchUserInfo(List<DocumentSnapshot> chats) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // Collect all unique user IDs from chats
    final userIds = <String>{};
    for (final chat in chats) {
      final data = chat.data() as Map<String, dynamic>;
      final chatUserIds = List<String>.from(data['userIds'] ?? []);
      userIds.addAll(chatUserIds.where((id) => id != currentUserId));
    }

    // Batch fetch users that aren't already cached
    if (userIds.isNotEmpty) {
      batchFetchUsers(userIds).catchError((error) {
        debugPrint("Error prefetching user info: $error");
        return <String, Map<String, String>>{};
      });
    }
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

    // Get user info from cache or show shimmer while loading
    Map<String, String>? userInfo;
    if (otherUserId.isNotEmpty && _userInfoCache.containsKey(otherUserId)) {
      userInfo = _userInfoCache[otherUserId];
    }

    if (userInfo == null) {
      // Start loading user info if not in cache
      if (otherUserId.isNotEmpty) {
        fetchChatPartnerInfo(userIds).then((_) {
          if (mounted) setState(() {});
        });
      }
      return _buildChatShimmer();
    }

    final chatName = userInfo['name'] ?? 'Unknown';
    final profileImageUrl = userInfo['profileImageUrl'] ?? '';
    
    bool isRead = false;
    if (user != null && chatData['lastMessageReadBy'] != null) {
      isRead = (chatData['lastMessageReadBy'] as List<dynamic>)
          .contains(user!.uid);
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
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            elevation: isSelected ? 4 : 1,
            shadowColor: isSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                : Colors.black.withOpacity(0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: isSelected
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : BorderSide.none,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 28,
                backgroundImage: profileImageUrl.isNotEmpty
                    ? NetworkImage(profileImageUrl)
                    : null,
                child: profileImageUrl.isEmpty
                    ? Text(
                        chatName.isNotEmpty ? chatName[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              title: Text(
                chatName,
                style: TextStyle(
                  fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                chatData['lastMessage'] ?? 'No messages yet',
                style: TextStyle(
                  color: isRead ? Colors.grey[600] : Colors.grey[800],
                  fontWeight: isRead ? FontWeight.normal : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeString,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                  if (!isRead) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () {
                HapticFeedback.lightImpact();

                if (widget.isDesktop) {
                  setState(() {
                    _selectedChatId = chatId;
                  });

                  if (widget.onChatSelected != null) {
                    widget.onChatSelected!(chatId, chatName);
                  }
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        chatId: chatId,
                      ),
                    ),
                  ).then((_) => _fetchChatList());
                }
              },
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
