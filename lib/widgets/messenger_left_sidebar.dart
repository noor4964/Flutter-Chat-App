import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/views/profile/profile_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';

class MessengerLeftSidebar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onIndexChanged;

  const MessengerLeftSidebar({
    Key? key,
    required this.currentIndex,
    required this.onIndexChanged,
  }) : super(key: key);

  @override
  _MessengerLeftSidebarState createState() => _MessengerLeftSidebarState();
}

class _MessengerLeftSidebarState extends State<MessengerLeftSidebar> {
  String? _userProfileImageUrl;
  String? _username;
  int _friendRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadFriendRequestCount();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          var userData = userDoc.data() as Map<String, dynamic>?;
          if (mounted) {
            setState(() {
              _userProfileImageUrl = userData?['profileImageUrl'];
              _username = userData?['username'] ?? user.displayName ?? 'User';
            });
          }
        }
      } catch (e) {
        print('Error loading user data: $e');
      }
    }
  }

  Future<void> _loadFriendRequestCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        QuerySnapshot connectionsSnapshot = await FirebaseFirestore.instance
            .collection('connections')
            .where('receiverId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'pending')
            .get();

        if (mounted) {
          setState(() {
            _friendRequestCount = connectionsSnapshot.docs.length;
          });
        }
      } catch (e) {
        print('Error loading friend request count: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor,
      child: Column(
        children: [
          // User Profile Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: _userProfileImageUrl != null
                      ? NetworkImage(_userProfileImageUrl!)
                      : null,
                  child: _userProfileImageUrl == null
                      ? Icon(Icons.person, size: 28)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _username ?? 'Loading...',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Online',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavItem(
                  context,
                  icon: Icons.home,
                  label: 'News Feed',
                  index: 0,
                  isSelected: widget.currentIndex == 0,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.chat_bubble,
                  label: 'Chats',
                  index: 1,
                  isSelected: widget.currentIndex == 1,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.auto_stories,
                  label: 'Stories',
                  index: 2,
                  isSelected: widget.currentIndex == 2,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.menu,
                  label: 'Menu',
                  index: 3,
                  isSelected: widget.currentIndex == 3,
                ),

                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(color: Theme.of(context).dividerColor),
                ),
                const SizedBox(height: 8),

                _buildNavItem(
                  context,
                  icon: Icons.people,
                  label: 'Friends',
                  index: -2, // Special navigation for friends
                  isSelected: false,
                  badge: _friendRequestCount > 0 ? _friendRequestCount : null,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.person,
                  label: 'Profile',
                  index: -3, // Special navigation for profile
                  isSelected: false,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.settings,
                  label: 'Settings',
                  index: -4, // Special navigation for settings
                  isSelected: false,
                ),
                _buildNavItem(
                  context,
                  icon: Icons.notifications,
                  label: 'Notifications',
                  index: -1, // Special case for notifications
                  isSelected: false,
                ),
              ],
            ),
          ),

          // Logout Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: InkWell(
              onTap: () => _showLogoutDialog(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int index,
    required bool isSelected,
    int? badge,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: () => _handleNavigation(context, index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).primaryColor.withOpacity(0.1)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).iconTheme.color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : null,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleNavigation(BuildContext context, int index) {
    if (index >= 0) {
      // Regular navigation (main tabs)
      widget.onIndexChanged(index);
    } else {
      // Special navigation
      switch (index) {
        case -2: // Friends
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UserListScreen()),
          );
          break;
        case -3: // Profile
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ProfileScreen()),
          );
          break;
        case -4: // Settings
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SettingsScreen()),
          );
          break;
        case -1: // Notifications
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notifications feature coming soon!')),
          );
          break;
      }
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await FirebaseAuth.instance.signOut();
                Navigator.of(context).pushReplacementNamed('/login');
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}