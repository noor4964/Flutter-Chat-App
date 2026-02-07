import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/providers/feed_provider.dart';
import 'package:flutter_chat_app/services/post_service.dart';
import 'package:flutter_chat_app/widgets/comments_bottom_sheet.dart';
import 'package:provider/provider.dart';
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
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyPost = currentUser?.uid == post.userId;

    return Container(
      color: isDark ? Colors.black : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Post header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.black.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: post.userProfileImage.isNotEmpty
                        ? CachedNetworkImageProvider(post.userProfileImage)
                        : null,
                    child: post.userProfileImage.isEmpty
                        ? Text(
                            post.username.isNotEmpty ? post.username[0] : 'U',
                            style: const TextStyle(fontSize: 14),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.username,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _buildPrivacyIcon(post.privacy),
                        ],
                      ),
                      if (post.location.isNotEmpty)
                        Text(
                          post.location,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white60 : Colors.grey[600],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (isMyPost)
                  IconButton(
                    icon: Icon(
                      Icons.more_horiz,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    onPressed: () => _showPostMenu(context, isDark),
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
              ],
            ),
          ),

          // ── Post image with double-tap-to-like ───────────────────
          if (post.imageUrl.isNotEmpty)
            _DoubleTapLikeImage(
              post: post,
              onTap: () => _showFullScreenImage(context, post.imageUrl),
            ),

          // ── Action icons row ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                _AnimatedLikeButton(post: post, showCount: false),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () =>
                      CommentsBottomSheet.show(context, postId: post.id),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      size: 24,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.send_outlined,
                    size: 24,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.bookmark_border,
                    size: 24,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // ── Like count (bold) ────────────────────────────────────
          if (post.likes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '${post.likes.length} ${post.likes.length == 1 ? 'like' : 'likes'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

          // ── Caption: username bold + caption inline ──────────────
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text: post.username,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: '  '),
                    TextSpan(text: post.caption),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // ── View all comments link ───────────────────────────────
          if (post.commentsCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: GestureDetector(
                onTap: () =>
                    CommentsBottomSheet.show(context, postId: post.id),
                child: Text(
                  'View all ${post.commentsCount} comment${post.commentsCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white54 : Colors.grey[500],
                  ),
                ),
              ),
            ),

          // ── Timestamp ────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.only(left: 14, right: 14, top: 4, bottom: 14),
            child: Text(
              timeago.format(post.timestamp),
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.white38 : Colors.grey[400],
                fontSize: 11,
              ),
            ),
          ),

          // ── Divider between posts ────────────────────────────────
          Divider(
            height: 1,
            thickness: 0.5,
            color: isDark
                ? Colors.white.withOpacity(0.10)
                : Colors.black.withOpacity(0.08),
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
    switch (privacy) {
      case PostPrivacy.public:
        icon = Icons.public;
        break;
      case PostPrivacy.friends:
        icon = Icons.people;
        break;
      case PostPrivacy.private:
        icon = Icons.lock;
        break;
    }
    return Icon(icon, size: 12, color: Colors.grey);
  }

  void _showPostMenu(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121212) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _buildMenuTile(
                ctx,
                icon: Icons.public,
                label: 'Public',
                isSelected: post.privacy == PostPrivacy.public,
                onTap: () {
                  Navigator.pop(ctx);
                  _changePrivacy(context, 'privacy_public');
                },
              ),
              _buildMenuTile(
                ctx,
                icon: Icons.people,
                label: 'Friends Only',
                isSelected: post.privacy == PostPrivacy.friends,
                onTap: () {
                  Navigator.pop(ctx);
                  _changePrivacy(context, 'privacy_friends');
                },
              ),
              _buildMenuTile(
                ctx,
                icon: Icons.lock,
                label: 'Private',
                isSelected: post.privacy == PostPrivacy.private,
                onTap: () {
                  Navigator.pop(ctx);
                  _changePrivacy(context, 'privacy_private');
                },
              ),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.08),
              ),
              _buildMenuTile(
                ctx,
                icon: Icons.delete_outline,
                label: 'Delete Post',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _deletePost(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool isSelected = false,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final color = isDestructive
        ? Colors.red
        : isSelected
            ? theme.colorScheme.primary
            : null;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: theme.colorScheme.primary, size: 20)
          : null,
      onTap: onTap,
    );
  }

  void _deletePost(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text(
            'Are you sure you want to delete this post? This action cannot be undone.'),
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

// ═══════════════════════════════════════════════════════════════════════════
// Animated Like Button — scale bounce + color transition
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedLikeButton extends StatefulWidget {
  final Post post;
  final bool showCount;
  const _AnimatedLikeButton({
    Key? key,
    required this.post,
    this.showCount = true,
  }) : super(key: key);

  @override
  State<_AnimatedLikeButton> createState() => _AnimatedLikeButtonState();
}

class _AnimatedLikeButtonState extends State<_AnimatedLikeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isLiked =
        currentUser != null && widget.post.isLikedBy(currentUser.uid);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _scaleAnimation,
          child: GestureDetector(
            onTap: _isProcessing ? null : () => _toggleLike(context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked
                    ? Colors.red
                    : (isDark ? Colors.white : Colors.black87),
                size: 26,
              ),
            ),
          ),
        ),
        if (widget.showCount)
          Text(
            widget.post.likes.length.toString(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
      ],
    );
  }

  Future<void> _toggleLike(BuildContext context) async {
    if (_isProcessing) return;
    _isProcessing = true;

    _controller.forward(from: 0);

    try {
      final feedProvider = Provider.of<FeedProvider>(context, listen: false);
      await feedProvider.toggleLike(widget.post.id);
    } finally {
      if (mounted) _isProcessing = false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Double-Tap-to-Like Image wrapper with heart overlay animation
// ═══════════════════════════════════════════════════════════════════════════

class _DoubleTapLikeImage extends StatefulWidget {
  final Post post;
  final VoidCallback onTap;

  const _DoubleTapLikeImage({
    Key? key,
    required this.post,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_DoubleTapLikeImage> createState() => _DoubleTapLikeImageState();
}

class _DoubleTapLikeImageState extends State<_DoubleTapLikeImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _heartAnimation;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _heartAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(
        CurvedAnimation(parent: _heartController, curve: Curves.easeOut));

    _heartController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _showHeart = false);
      }
    });
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: _onDoubleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Edge-to-edge image — no ClipRRect, no borderRadius
          CachedNetworkImage(
            imageUrl: widget.post.imageUrl,
            width: double.infinity,
            fit: BoxFit.cover,
            memCacheWidth: 800,
            placeholder: (context, url) => Container(
              height: 300,
              color: isDark ? const Color(0xFF121212) : const Color(0xFFF0F0F3),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              height: 250,
              color: isDark ? const Color(0xFF121212) : const Color(0xFFF0F0F3),
              child: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ),
            ),
          ),

          // Heart overlay
          if (_showHeart)
            ScaleTransition(
              scale: _heartAnimation,
              child: const Icon(
                Icons.favorite,
                color: Colors.white,
                size: 80,
                shadows: [
                  Shadow(blurRadius: 20, color: Colors.black54),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _onDoubleTap() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final alreadyLiked = widget.post.isLikedBy(currentUser.uid);

    setState(() => _showHeart = true);
    _heartController.forward(from: 0);

    if (!alreadyLiked) {
      final feedProvider = Provider.of<FeedProvider>(context, listen: false);
      feedProvider.toggleLike(widget.post.id);
    }
  }
}
