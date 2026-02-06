import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/services/post_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class PostCard extends StatelessWidget {
  final Post post;
  final Function? onPrivacyChanged;

  const PostCard({
    Key? key,
    required this.post,
    this.onPrivacyChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyPost = currentUser?.uid == post.userId;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Post header with user info and privacy
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: post.userProfileImage.isNotEmpty
                      ? NetworkImage(post.userProfileImage)
                      : null,
                  child: post.userProfileImage.isEmpty
                      ? Text(post.username.isNotEmpty ? post.username[0] : 'U')
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.username,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            timeago.format(post.timestamp),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 6),
                          _buildPrivacyIcon(post.privacy),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isMyPost)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deletePost(context);
                      } else if (value.startsWith('privacy_')) {
                        _changePrivacy(context, value);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'privacy_public',
                        child: _buildPrivacyMenuItem(
                          Icons.public,
                          'Public',
                          post.privacy == PostPrivacy.public,
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'privacy_friends',
                        child: _buildPrivacyMenuItem(
                          Icons.people,
                          'Friends Only',
                          post.privacy == PostPrivacy.friends,
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'privacy_private',
                        child: _buildPrivacyMenuItem(
                          Icons.lock,
                          'Private',
                          post.privacy == PostPrivacy.private,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete, color: Colors.red),
                          title: Text('Delete Post', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Post caption
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              child: Text(
                post.caption,
                style: theme.textTheme.bodyLarge,
              ),
            ),

          // Post image with caching
          if (post.imageUrl.isNotEmpty)
            GestureDetector(
              onTap: () => _showFullScreenImage(context, post.imageUrl),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: post.imageUrl,
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.cover,
                  memCacheWidth: 800,
                  placeholder: (context, url) => Container(
                    height: 250,
                    color: Colors.grey[200],
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 200,
                    color: Colors.grey[300],
                    child: const Center(
                      child: Icon(Icons.error),
                    ),
                  ),
                ),
              ),
            ),

          // Like and comment actions
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                _LikeButton(post: post),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.comment_outlined),
                  onPressed: () {
                    // Open comments - would be implemented in a comments feature
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  post.commentsCount.toString(),
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                if (post.location.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        post.location,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          extendBodyBehindAppBar: true,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyIcon(PostPrivacy privacy) {
    IconData icon;
    Color color;
    
    switch (privacy) {
      case PostPrivacy.public:
        icon = Icons.public;
        color = Colors.green;
        break;
      case PostPrivacy.friends:
        icon = Icons.people;
        color = Colors.blue;
        break;
      case PostPrivacy.private:
        icon = Icons.lock;
        color = Colors.red;
        break;
    }
    
    return Icon(icon, size: 14, color: color);
  }

  Widget _buildPrivacyMenuItem(IconData icon, String text, bool isSelected) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: isSelected ? Colors.blue : null),
      title: Text(
        text,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue : null,
        ),
      ),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
    );
  }

  void _deletePost(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final postService = PostService();
              postService.deletePost(post.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Post deleted')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _changePrivacy(BuildContext context, String value) {
    PostPrivacy newPrivacy;
    
    switch (value) {
      case 'privacy_public':
        newPrivacy = PostPrivacy.public;
        break;
      case 'privacy_friends':
        newPrivacy = PostPrivacy.friends;
        break;
      case 'privacy_private':
        newPrivacy = PostPrivacy.private;
        break;
      default:
        return;
    }
    
    if (newPrivacy != post.privacy) {
      final postService = PostService();
      postService.updatePrivacy(post.id, newPrivacy);
      
      String privacyText;
      switch (newPrivacy) {
        case PostPrivacy.public:
          privacyText = 'public';
          break;
        case PostPrivacy.friends:
          privacyText = 'friends only';
          break;
        case PostPrivacy.private:
          privacyText = 'private';
          break;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post changed to $privacyText')),
      );
      
      if (onPrivacyChanged != null) {
        onPrivacyChanged!();
      }
    }
  }
}

class _LikeButton extends StatefulWidget {
  final Post post;

  const _LikeButton({
    Key? key,
    required this.post,
  }) : super(key: key);

  @override
  _LikeButtonState createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> {
  bool _isLiking = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isLiked = currentUser != null && widget.post.isLikedBy(currentUser.uid);

    return Row(
      children: [
        IconButton(
          icon: Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            color: isLiked ? Colors.red : null,
          ),
          onPressed: _isLiking ? null : _toggleLike,
        ),
        Text(
          widget.post.likes.length.toString(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Future<void> _toggleLike() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    if (_isLiking) return;

    setState(() {
      _isLiking = true;
    });

    try {
      final postService = PostService();
      await postService.toggleLike(widget.post.id);
    } finally {
      if (mounted) {
        setState(() {
          _isLiking = false;
        });
      }
    }
  }
}
