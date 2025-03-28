import 'package:flutter/material.dart';
import 'package:flutter_chat_app/views/chat/chat_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/views/profile/profile_screen.dart';
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';
import 'package:flutter_chat_app/views/pending_requests_screen.dart';

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
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: [
          // Chats Screen
          _buildChatsSection(),

          // Stories Screen
          _buildStoriesSection(),

          // Menu Screen
          _buildMenuSection(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          });
        },
        backgroundColor: theme.scaffoldBackgroundColor,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_stories_outlined),
            activeIcon: Icon(Icons.auto_stories),
            label: 'Stories',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            activeIcon: Icon(Icons.menu),
            label: 'Menu',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0 && width >= 768
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => UserListScreen()),
                );
              },
              child: const Icon(Icons.create),
              tooltip: 'Start a new conversation',
            )
          : null,
    );
  }

  // Chats Section - Show existing chat list
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
                    // Add story functionality
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Create a story coming soon!')),
                    );
                  },
                  tooltip: 'Add to story',
                ),
              ],
            ),
          ),

          // Your Story Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
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

          const SizedBox(height: 16),

          // Stories list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: 10, // Mock stories count
              itemBuilder: (context, index) {
                // Demo data - in a real app, you'd fetch this from your database
                final bool hasUnseenStory = index % 3 == 0;
                final String name = "User ${index + 1}";
                final String time = "${(index % 12) + 1}h ago";

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: () {
                      // View story
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Viewing $name\'s story')),
                      );
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
                              child: Text(
                                name.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: hasUnseenStory
                                      ? colorScheme.primary
                                      : Colors.grey[700],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: hasUnseenStory
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
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
                              // More options for this story
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Menu Section
  Widget _buildMenuSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUser = FirebaseAuth.instance.currentUser;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header with title
          Text(
            'Menu',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onBackground,
            ),
          ),

          const SizedBox(height: 16),

          // User profile card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfileScreen()),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: colorScheme.primaryContainer,
                      backgroundImage: _getUserProfileImage(),
                      child: _getUserProfileImage() == null
                          ? Text(
                              _getUserInitials(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentUser?.displayName ?? 'Chat User',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentUser?.email ?? '',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'View your profile',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
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

          const SizedBox(height: 24),

          // Menu sections
          _buildMenuSectionHeader('General', [
            _buildMenuItem(
              icon: Icons.person_add,
              title: 'New Contact',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => UserListScreen()),
                );
              },
            ),
            _buildMenuItem(
              icon: Icons.notifications,
              title: 'Pending Requests',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => PendingRequestsScreen()),
                );
              },
              badge: '3', // Example badge number - would be dynamic in real app
            ),
          ]),

          const SizedBox(height: 16),

          _buildMenuSectionHeader('Preferences', [
            _buildMenuItem(
              icon: Icons.settings,
              title: 'Settings',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen()),
                );
              },
            ),
            _buildMenuItem(
              icon: Icons.help_outline,
              title: 'Help & Support',
              onTap: () {
                // Open help page
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Help & Support coming soon!')),
                );
              },
            ),
          ]),

          const SizedBox(height: 16),

          _buildMenuSectionHeader('Account', [
            _buildMenuItem(
              icon: Icons.logout,
              title: 'Sign Out',
              onTap: () async {
                // Logout confirmation dialog
                bool confirm = await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sign Out'),
                        content:
                            const Text('Are you sure you want to sign out?'),
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

                try {
                  await FirebaseAuth.instance.signOut();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sign out error: $e')),
                    );
                  }
                }
              },
              textColor: Colors.red,
              iconColor: Colors.red,
            ),
          ]),
        ],
      ),
    );
  }

  // Helper method to build menu sections (renamed to avoid conflict)
  Widget _buildMenuSectionHeader(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...items,
      ],
    );
  }

  // Helper method to build menu items
  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? badge,
    Color? iconColor,
    Color? textColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: Colors.grey.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor != null
                      ? iconColor.withOpacity(0.1)
                      : colorScheme.primaryContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to get user profile image
  ImageProvider? _getUserProfileImage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.photoURL != null) {
      return NetworkImage(user!.photoURL!);
    }
    return null;
  }

  // Helper method to get user initials
  String _getUserInitials() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      return user.displayName![0].toUpperCase();
    } else if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email![0].toUpperCase();
    }
    return '?';
  }
}
