import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/providers/notification_provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/widgets/glass_scaffold.dart';
import 'package:flutter_chat_app/widgets/glass_container.dart';
import 'package:flutter_chat_app/views/pending_requests_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    // Mark all activities as read when the screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().markAllActivitiesAsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.isGlassMode;

    return GlassScaffold(
      appBar: isGlass
          ? GlassAppBar(
              title: const Text('Notifications'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : AppBar(
              title: const Text('Notifications'),
              elevation: 0,
              backgroundColor: isDark ? Colors.black : Colors.white,
              foregroundColor: isDark ? Colors.white : Colors.black,
            ),
      body: Consumer<NotificationProvider>(
        builder: (context, notifProvider, _) {
          final activities = notifProvider.activities;
          final pendingCount = notifProvider.pendingRequestCount;

          final bool hasContent =
              activities.isNotEmpty || pendingCount > 0;

          if (!hasContent) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: colorScheme.primary.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When someone likes or comments on your post,\nyou\'ll see it here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8),
            itemCount: activities.length + (pendingCount > 0 ? 1 : 0),
            itemBuilder: (context, index) {
              // Friend requests card at the top
              if (pendingCount > 0 && index == 0) {
                return _buildFriendRequestCard(
                    context, pendingCount, colorScheme, isDark);
              }

              final activityIndex =
                  pendingCount > 0 ? index - 1 : index;
              final activity = activities[activityIndex];
              return _buildActivityTile(
                  context, activity, colorScheme, isDark);
            },
          );
        },
      ),
    );
  }

  Widget _buildFriendRequestCard(
    BuildContext context,
    int count,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PendingRequestsScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey[200]!,
            ),
          ),
        ),
        child: Row(
          children: [
            // Stacked avatar placeholder
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withOpacity(0.7),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Friend Requests',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count == 1
                        ? '1 pending request'
                        : '$count pending requests',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTile(
    BuildContext context,
    Map<String, dynamic> activity,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final type = activity['type'] as String? ?? '';
    final actorName = activity['actorName'] as String? ?? 'Someone';
    final actorImage = activity['actorImage'] as String? ?? '';
    final isRead = activity['isRead'] == true;
    final commentPreview = activity['commentPreview'] as String? ?? '';

    // Build description
    String description;
    IconData typeIcon;
    Color typeIconColor;

    switch (type) {
      case 'like':
        description = 'liked your post.';
        typeIcon = Icons.favorite;
        typeIconColor = Colors.red;
        break;
      case 'comment':
        description = commentPreview.isNotEmpty
            ? 'commented: $commentPreview'
            : 'commented on your post.';
        typeIcon = Icons.chat_bubble;
        typeIconColor = colorScheme.primary;
        break;
      default:
        description = 'interacted with your content.';
        typeIcon = Icons.notifications;
        typeIconColor = Colors.grey;
    }

    // Parse timestamp
    final timestamp = activity['timestamp'];
    String timeAgo = '';
    if (timestamp is Timestamp) {
      timeAgo = _getTimeAgo(timestamp.toDate());
    }

    return Container(
      color: isRead
          ? null
          : (isDark
              ? colorScheme.primary.withOpacity(0.08)
              : colorScheme.primary.withOpacity(0.04)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Actor avatar
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: actorImage.isNotEmpty
                      ? NetworkImage(actorImage)
                      : null,
                  child: actorImage.isEmpty
                      ? Text(
                          actorName.isNotEmpty
                              ? actorName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        )
                      : null,
                ),
                // Small type indicator
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: typeIconColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.black : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      typeIcon,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Activity text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      children: [
                        TextSpan(
                          text: actorName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' '),
                        TextSpan(text: description),
                      ],
                    ),
                  ),
                  if (timeAgo.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
