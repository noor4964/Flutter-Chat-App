import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';

class WebLayoutWrapper extends StatelessWidget {
  final Widget child;
  final Widget? leftSidebar;
  final Widget? rightSidebar;
  final String? title;
  final bool showLeftSidebar;
  final bool showRightSidebar;
  final double leftSidebarWidth;
  final double rightSidebarWidth;

  const WebLayoutWrapper({
    Key? key,
    required this.child,
    this.leftSidebar,
    this.rightSidebar,
    this.title,
    this.showLeftSidebar = true,
    this.showRightSidebar = true,
    this.leftSidebarWidth = 280,
    this.rightSidebarWidth = 280,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // For non-web platforms, return the child as-is
    if (!PlatformHelper.isWeb) {
      return child;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    
    // For small screens on web, use mobile layout
    if (screenWidth < 1200) {
      return child;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // Left Sidebar
          if (showLeftSidebar) ...[
            Container(
              width: leftSidebarWidth,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: leftSidebar ?? _buildDefaultLeftSidebar(context),
            ),
          ],
          
          // Main Content Area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
              child: Column(
                children: [
                  // Optional title bar for web
                  if (title != null)
                    Container(
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
                          Text(
                            title!,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // Main content
                  Expanded(child: child),
                ],
              ),
            ),
          ),
          
          // Right Sidebar
          if (showRightSidebar) ...[
            Container(
              width: rightSidebarWidth,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: rightSidebar ?? _buildDefaultRightSidebar(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDefaultLeftSidebar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Navigation',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildSidebarItem(
            context,
            icon: Icons.home,
            label: 'Home',
            onTap: () => Navigator.pushReplacementNamed(context, '/home'),
          ),
          _buildSidebarItem(
            context,
            icon: Icons.chat,
            label: 'Chats',
            onTap: () => Navigator.pushReplacementNamed(context, '/chats'),
          ),
          _buildSidebarItem(
            context,
            icon: Icons.people,
            label: 'Friends',
            onTap: () => Navigator.pushReplacementNamed(context, '/friends'),
          ),
          _buildSidebarItem(
            context,
            icon: Icons.feed,
            label: 'News Feed',
            onTap: () => Navigator.pushReplacementNamed(context, '/feed'),
          ),
          _buildSidebarItem(
            context,
            icon: Icons.person,
            label: 'Profile',
            onTap: () => Navigator.pushReplacementNamed(context, '/profile'),
          ),
          _buildSidebarItem(
            context,
            icon: Icons.settings,
            label: 'Settings',
            onTap: () => Navigator.pushReplacementNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultRightSidebar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildQuickActionCard(
            context,
            icon: Icons.add,
            title: 'Create Post',
            subtitle: 'Share something new',
            onTap: () => Navigator.pushNamed(context, '/create-post'),
          ),
          const SizedBox(height: 12),
          _buildQuickActionCard(
            context,
            icon: Icons.video_call,
            title: 'Start Call',
            subtitle: 'Make a video call',
            onTap: () => Navigator.pushNamed(context, '/start-call'),
          ),
          const SizedBox(height: 12),
          _buildQuickActionCard(
            context,
            icon: Icons.group_add,
            title: 'Find Friends',
            subtitle: 'Discover new people',
            onTap: () => Navigator.pushNamed(context, '/find-friends'),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                size: 20,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}