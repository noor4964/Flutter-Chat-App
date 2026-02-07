import 'package:flutter/material.dart';
import 'package:flutter_chat_app/views/chat/chat_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/views/social/news_feed_screen.dart';
import 'package:flutter_chat_app/views/post/post_create_screen.dart';
import 'package:flutter_chat_app/services/firebase_error_handler.dart';
import 'package:flutter_chat_app/widgets/error_boundary.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/views/create_story_screen.dart';
import 'package:flutter_chat_app/views/story_view_screen.dart';
import 'package:flutter_chat_app/models/story_model.dart';
import 'package:flutter_chat_app/services/story_service.dart';
import 'package:flutter_chat_app/views/profile/profile_tab_screen.dart';
import 'package:flutter_chat_app/widgets/web_layout_wrapper.dart';
import 'package:flutter_chat_app/widgets/messenger_left_sidebar.dart';
import 'package:flutter_chat_app/widgets/messenger_right_sidebar.dart';
import 'package:flutter_chat_app/widgets/chat_layout_with_main_sidebar.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';

class MessengerHomeScreen extends StatefulWidget {
  final bool isDesktop;

  const MessengerHomeScreen({
    Key? key,
    this.isDesktop = false,
  }) : super(key: key);

  @override
  _MessengerHomeScreenState createState() => _MessengerHomeScreenState();
}

class _MessengerHomeScreenState extends State<MessengerHomeScreen> {
  int _currentIndex = 0;
  final FirebaseErrorHandler _errorHandler = FirebaseErrorHandler();
  bool _isMounted = false;

  // State variable to store user profile image URL
  String? _userProfileImageUrl;

  // State variables for selected chat (persisted across layout changes)
  String? _selectedChatId;
  String? _selectedChatName;
  String? _selectedChatProfileUrl;
  bool _selectedChatIsOnline = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _loadUserProfileData(); // Load profile data when screen initializes
  }

  @override
  void dispose() {
    _isMounted = false;
    super.dispose();
  }

  // Load user profile data from Firestore
  Future<void> _loadUserProfileData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        var userData = userDoc.data() as Map<String, dynamic>?;
        String? profileImageUrl = userData?['profileImageUrl'];

        if (_isMounted && mounted) {
          setState(() {
            _userProfileImageUrl = profileImageUrl;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading user profile data: $e');
    }
  }

  // Safe setState that checks if widget is mounted before updating state
  void _safeSetState(Function() function) {
    if (_isMounted && mounted) {
      setState(function);
    }
  }

  // Safe navigation method — IndexedStack just uses _currentIndex
  void _safeNavigateToIndex(int index) {
    if (index < 0 || index >= 4) return;
    
    _safeSetState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Define page titles for web layout
    final pageTitles = [
      'News Feed',
      'Chats',
      'Stories',
      'Profile'
    ];

    // Main content widget — IndexedStack keeps all pages alive.
    // NewsFeedScreen is const so Flutter reuses the same instance.
    Widget mainContent = IndexedStack(
      index: _currentIndex,
      children: [
        _buildErrorSafeScreen(const NewsFeedScreen()),
        _buildErrorSafeScreen(_buildChatsSection()),
        _buildErrorSafeScreen(_buildStoriesSection()),
        _buildErrorSafeScreen(ProfileTabScreen(onProfileUpdated: _loadUserProfileData)),
      ],
    );

    // For web platforms with sufficient width, use the three-column layout.
    // Key fix: ChatLayoutWithMainSidebar is rendered alongside the
    // IndexedStack via a Stack + Offstage, so the IndexedStack (and its
    // children like NewsFeedScreen) is NEVER removed from the widget tree.
    if (PlatformHelper.isWeb && MediaQuery.of(context).size.width >= 1200) {
      final bool isChatsTab = _currentIndex == 1;

      return Stack(
        children: [
          // Non-chat tabs: WebLayoutWrapper with the IndexedStack inside
          Offstage(
            offstage: isChatsTab,
            child: WebLayoutWrapper(
              title: pageTitles[_currentIndex],
              leftSidebar: MessengerLeftSidebar(
                currentIndex: _currentIndex,
                onIndexChanged: (index) {
                  _safeNavigateToIndex(index);
                },
              ),
              rightSidebar: MessengerRightSidebar(
                currentIndex: _currentIndex,
              ),
              child: mainContent,
            ),
          ),

          // Chats tab: the special three-column chat layout
          Offstage(
            offstage: !isChatsTab,
            child: ChatLayoutWithMainSidebar(
              isDesktop: true,
              currentIndex: _currentIndex,
              onIndexChanged: (index) {
                _safeNavigateToIndex(index);
              },
              initialChatId: _selectedChatId,
              initialChatName: _selectedChatName,
              initialChatProfileUrl: _selectedChatProfileUrl,
              initialChatIsOnline: _selectedChatIsOnline,
              onChatSelected: (chatId, chatName, profileUrl, isOnline) {
                setState(() {
                  _selectedChatId = chatId;
                  _selectedChatName = chatName;
                  _selectedChatProfileUrl = profileUrl;
                  _selectedChatIsOnline = isOnline;
                });
              },
            ),
          ),
        ],
      );
    }

    // For mobile or small screens, use the traditional layout
    return Scaffold(
      body: mainContent,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          _safeNavigateToIndex(index);
        },
        backgroundColor: theme.scaffoldBackgroundColor,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.view_list),
            activeIcon: Icon(Icons.view_list),
            label: 'Feed',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.auto_stories_outlined),
            activeIcon: Icon(Icons.auto_stories),
            label: 'Stories',
          ),
          BottomNavigationBarItem(
            icon: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.transparent,
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.grey[300],
                backgroundImage: _getUserProfileImage(),
                child: _getUserProfileImage() == null
                    ? Icon(Icons.person, size: 16, color: Colors.grey[600])
                    : null,
              ),
            ),
            activeIcon: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.primary,
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.grey[300],
                backgroundImage: _getUserProfileImage(),
                child: _getUserProfileImage() == null
                    ? Icon(Icons.person, size: 16, color: Colors.grey[600])
                    : null,
              ),
            ),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: _shouldShowFab()
          ? FloatingActionButton(
              onPressed: () {
                try {
                  if (_currentIndex == 0) {
                    // Create new post - use the PostCreateScreen (Feed tab)
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        opaque: false,
                        pageBuilder: (BuildContext context, _, __) {
                          return PostCreateScreen();
                        },
                      ),
                    );
                  } else if (_currentIndex == 1) {
                    // Start new chat (Chats tab)
                    _safeNavigate(context, UserListScreen());
                  } else if (_currentIndex == 2) {
                    // Create new story - navigate to CreateStoryScreen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateStoryScreen(),
                      ),
                    ).then((result) {
                      // Refresh data when returning from story creation
                      if (result == true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Story created successfully!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    });
                  }
                } catch (e) {
                  print('❌ Error in FAB action: $e');
                  if (_isMounted && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Action failed: Please try again')),
                    );
                  }
                }
              },
              child: Icon(_currentIndex == 0
                  ? Icons.create
                  : _currentIndex == 1
                      ? Icons.add_photo_alternate
                      : _currentIndex == 2
                          ? Icons.add_circle_outline
                          : Icons.add),
              tooltip: _currentIndex == 0
                  ? 'Start a new conversation'
                  : _currentIndex == 1
                      ? 'Create post'
                      : _currentIndex == 2
                          ? 'Create story'
                          : 'Add new',
            )
          : null,
    );
  }

  bool _shouldShowFab() {
    // Show FAB on Feed tab, Chats tab (desktop/tablet only), and Stories tab
    return (_currentIndex == 0) ||
        (_currentIndex == 1 && MediaQuery.of(context).size.width >= 768) ||
        (_currentIndex == 2);
  }

  // Chats Section - Show chat list (web layout is handled in build method)
  Widget _buildChatsSection() {
    return ChatListScreen(
      isDesktop: widget.isDesktop,
      hideAppBar: true, // We'll handle appbar in this screen
    );
  }

  // Stories Section - Similar to Facebook Messenger
  Widget _buildStoriesSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final storyService = StoryService();

    return SafeArea(
      child: Column(
        children: [
          // Stories AppBar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Text(
                  'Stories',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onBackground,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    // Navigate to CreateStoryScreen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateStoryScreen(),
                      ),
                    ).then((result) {
                      // Refresh data when returning from story creation
                      if (result == true) {
                        setState(() {}); // Refresh the list
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Story created successfully!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    });
                  },
                  tooltip: 'Add to story',
                ),
              ],
            ),
          ),

          // Your Story Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: GestureDetector(
              onTap: () {
                // Navigate to CreateStoryScreen when the card is tapped
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateStoryScreen(),
                  ),
                ).then((result) {
                  // Refresh data when returning from story creation
                  if (result == true) {
                    setState(() {}); // Refresh the list
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Story created successfully!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                });
              },
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: colorScheme.primaryContainer,
                            backgroundImage: _getUserProfileImage(),
                            child: _getUserProfileImage() == null
                                ? Text(
                                    _getUserInitials(),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.scaffoldBackgroundColor,
                                  width: 2,
                                ),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.add,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add to your story',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Share a photo, video or write something',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
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

          const SizedBox(height: 16),

          // Real stories list fetched from database
          Expanded(
            child: StreamBuilder<List<Story>>(
              stream: storyService.getActiveStories(context: context),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.orange),
                        const SizedBox(height: 16),
                        Text('Error loading stories: ${snapshot.error}'),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final List<Story> stories = snapshot.data ?? [];

                if (stories.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_stories_outlined,
                          size: 64,
                          color: colorScheme.primary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No stories yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Stories from your contacts will appear here',
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Group stories by user
                final Map<String, List<Story>> groupedStories =
                    storyService.groupStoriesByUser(stories);
                final List<String> userIds = groupedStories.keys.toList();
                final String? currentUserId =
                    FirebaseAuth.instance.currentUser?.uid;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: userIds.length,
                  itemBuilder: (context, index) {
                    final String userId = userIds[index];
                    final List<Story> userStories =
                        groupedStories[userId] ?? [];

                    if (userStories.isEmpty) return const SizedBox.shrink();

                    // Get the first story to display user info
                    final Story firstStory = userStories.first;
                    final bool hasUnseenStory = currentUserId != null &&
                        !userStories
                            .any((story) => story.isViewed(currentUserId));

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () {
                          // View story - open StoryViewScreen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StoryViewScreen(
                                stories: userStories,
                                userId: userId,
                                initialIndex: 0,
                              ),
                            ),
                          ).then((_) {
                            // Refresh the list when returning
                            setState(() {});
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: hasUnseenStory
                                      ? Border.all(
                                          color: colorScheme.primary,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: hasUnseenStory
                                      ? colorScheme.primaryContainer
                                      : Colors.grey.withOpacity(0.2),
                                  backgroundImage:
                                      firstStory.userProfileImage.isNotEmpty
                                          ? NetworkImage(
                                              firstStory.userProfileImage)
                                          : null,
                                  child: firstStory.userProfileImage.isEmpty
                                      ? Text(
                                          firstStory.username.isNotEmpty
                                              ? firstStory.username[0]
                                                  .toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: hasUnseenStory
                                                ? colorScheme.primary
                                                : Colors.grey[700],
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      firstStory.username,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: hasUnseenStory
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          _getTimeAgo(firstStory.timestamp),
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          _getPrivacyIcon(firstStory.privacy),
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          _getPrivacyText(firstStory.privacy),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.more_horiz,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () {
                                  _showStoryOptions(firstStory, userStories);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Display time ago for stories
  String _getTimeAgo(DateTime dateTime) {
    final Duration difference = DateTime.now().difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  // Show story options
  void _showStoryOptions(Story story, List<Story> allUserStories) {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final bool isOwnStory = story.userId == currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle for the bottom sheet
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              ListTile(
                leading: const Icon(Icons.remove_red_eye_outlined),
                title: const Text('View story'),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate directly to StoryViewScreen without unnecessary complexity
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StoryViewScreen(
                        stories: allUserStories,
                        userId: story.userId,
                        initialIndex: allUserStories.indexOf(story),
                      ),
                    ),
                  ).then((_) {
                    // Refresh the list when returning
                    setState(() {});
                  });
                },
              ),

              if (isOwnStory) ...[
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete story'),
                  onTap: () async {
                    Navigator.pop(context);

                    // Show confirmation dialog
                    final bool confirm = await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Story'),
                            content: const Text(
                                'Are you sure you want to delete this story?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ) ??
                        false;

                    if (confirm) {
                      try {
                        final storyService = StoryService();
                        await storyService.deleteStory(story.id,
                            context: context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Story deleted'),
                            backgroundColor: Colors.green,
                          ),
                        );

                        // Refresh the list
                        setState(() {});
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to delete story: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.report_outlined),
                  title: const Text('Report story'),
                  onTap: () {
                    Navigator.pop(context);
                    // Report story functionality
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Report functionality coming soon')),
                    );
                  },
                ),
              ],

              // Add some padding at the bottom
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to get user profile image with error handling
  ImageProvider? _getUserProfileImage() {
    try {
      // First check if we have a profile image URL from Firestore
      if (_userProfileImageUrl != null) {
        return NetworkImage(_userProfileImageUrl!);
      }

      // If not, try Firebase Auth as fallback
      final user = FirebaseAuth.instance.currentUser;
      if (user?.photoURL != null) {
        return NetworkImage(user!.photoURL!);
      }
    } catch (e) {
      print('❌ Error getting user profile image: $e');
      // Return null instead of crashing
    }
    return null;
  }

  // Helper method to get user initials with error handling
  String _getUserInitials() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.displayName != null && user!.displayName!.isNotEmpty) {
        return user.displayName![0].toUpperCase();
      } else if (user?.email != null && user!.email!.isNotEmpty) {
        return user.email![0].toUpperCase();
      }
    } catch (e) {
      print('❌ Error getting user initials: $e');
      // Return a fallback value instead of crashing
    }
    return '?';
  }

  // Safely navigate to a new page with error handling
  Future<void> _safeNavigate(BuildContext context, Widget destination) async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => destination),
      );
    } catch (e) {
      print('❌ Navigation error: $e');
      if (_isMounted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigation error: Please try again')),
        );
      }
    }
  }

  // Build a proper error boundary widget
  Widget _buildErrorSafeScreen(Widget screen) {
    return ErrorBoundary(child: screen);
  }

  // Get privacy icon based on story privacy
  IconData _getPrivacyIcon(StoryPrivacy privacy) {
    switch (privacy) {
      case StoryPrivacy.public:
        return Icons.public;
      case StoryPrivacy.friends:
        return Icons.group;
      case StoryPrivacy.private:
        return Icons.lock;
      default:
        return Icons.group;
    }
  }

  // Get privacy text based on story privacy
  String _getPrivacyText(StoryPrivacy privacy) {
    switch (privacy) {
      case StoryPrivacy.public:
        return 'Public';
      case StoryPrivacy.friends:
        return 'Friends';
      case StoryPrivacy.private:
        return 'Private';
      default:
        return 'Friends';
    }
  }
}
