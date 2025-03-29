import 'package:flutter/material.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/services/feed_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class PostCard extends StatefulWidget {
  final Post post;
  final Function()? onTap;

  const PostCard({Key? key, required this.post, this.onTap}) : super(key: key);

  @override
  _PostCardState createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  final FeedService _feedService = FeedService();
  late bool _isLiked;
  late int _likeCount;
  late int _commentsCount;
  final TextEditingController _commentController = TextEditingController();
  late AnimationController _likeAnimationController;
  bool _isDoubleTapping = false;

  // Stream subscription for real-time post updates
  StreamSubscription<Post>? _postSubscription;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLikedBy(_feedService.currentUserId ?? '');
    _likeCount = widget.post.likes.length;
    _commentsCount = widget.post.commentsCount;

    _likeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Subscribe to real-time updates for this post
    _postSubscription =
        _feedService.getPostById(widget.post.id).listen((updatedPost) {
      if (mounted) {
        setState(() {
          _isLiked = updatedPost.isLikedBy(_feedService.currentUserId ?? '');
          _likeCount = updatedPost.likes.length;
          _commentsCount = updatedPost.commentsCount;
        });
      }
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _likeAnimationController.dispose();
    _postSubscription?.cancel();
    super.dispose();
  }

  void _handleLikePost() {
    setState(() {
      if (_isLiked) {
        _likeCount--;
      } else {
        _likeCount++;
        _likeAnimationController
            .forward()
            .then((_) => _likeAnimationController.reverse());
      }
      _isLiked = !_isLiked;
    });

    _feedService.toggleLike(widget.post.id);
  }

  void _handleDoubleTap() {
    if (_isDoubleTapping) return;

    setState(() {
      _isDoubleTapping = true;
    });

    if (!_isLiked) {
      setState(() {
        _isLiked = true;
        _likeCount++;
      });
      _feedService.toggleLike(widget.post.id);
    }

    _likeAnimationController.forward().then((_) {
      _likeAnimationController.reverse().then((_) {
        setState(() {
          _isDoubleTapping = false;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? colorScheme.surface
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Post header with user info
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: widget.post.userProfileImage.isNotEmpty
                      ? NetworkImage(widget.post.userProfileImage)
                      : null,
                  backgroundColor: colorScheme.primaryContainer,
                  child: widget.post.userProfileImage.isEmpty
                      ? Text(
                          widget.post.username.isNotEmpty
                              ? widget.post.username[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.post.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (widget.post.location.isNotEmpty)
                        Text(
                          widget.post.location,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  splashRadius: 20,
                  onPressed: () {
                    _showPostOptions(context);
                  },
                ),
              ],
            ),
          ),

          // Image
          GestureDetector(
            onDoubleTap: _handleDoubleTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 1.0, // Square aspect ratio like Instagram
                  child: CachedNetworkImage(
                    imageUrl: widget.post.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[300],
                      child: const Icon(
                        Icons.image_not_supported,
                        size: 50,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                // Heart animation on double tap
                AnimatedBuilder(
                  animation: _likeAnimationController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 + _likeAnimationController.value * 0.8,
                      child: Opacity(
                        opacity: _likeAnimationController.value,
                        child: const Icon(
                          Icons.favorite,
                          color: Colors.white,
                          size: 100,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isLiked ? Icons.favorite : Icons.favorite_border,
                    color: _isLiked ? Colors.red : null,
                  ),
                  onPressed: _handleLikePost,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () {
                    _showCommentSheet(context);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Share feature coming soon!'),
                      ),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.bookmark_border),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Save feature coming soon!'),
                      ),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              ],
            ),
          ),

          // Likes count
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Text(
              '$_likeCount like${_likeCount != 1 ? 's' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),

          // Caption
          if (widget.post.caption.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: theme.brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  children: [
                    TextSpan(
                      text: '${widget.post.username} ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: widget.post.caption),
                  ],
                ),
              ),
            ),

          // Comments count
          if (widget.post.commentsCount > 0)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: GestureDetector(
                onTap: () {
                  _showCommentSheet(context);
                },
                child: Text(
                  'View all ${widget.post.commentsCount} comment${widget.post.commentsCount != 1 ? 's' : ''}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          // Timestamp
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 12.0),
            child: Text(
              timeago.format(widget.post.timestamp),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPostOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.bookmark_border),
                title: const Text('Save'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Save feature coming soon!'),
                    ),
                  );
                },
              ),
              if (widget.post.userId == _feedService.currentUserId)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(context);

                    // Confirm deletion
                    bool confirm = await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Post'),
                            content: const Text(
                                'Are you sure you want to delete this post?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ) ??
                        false;

                    if (confirm) {
                      try {
                        await _feedService.deletePost(widget.post.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Post deleted successfully'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error deleting post: $e'),
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Share feature coming soon!'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Report'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Report feature coming soon!'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showCommentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(),
                // Comments list
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _feedService.getComments(widget.post.id,
                        context: context),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error loading comments: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      final comments = snapshot.data ?? [];

                      if (comments.isEmpty) {
                        return const Center(
                          child:
                              Text('No comments yet. Be the first to comment!'),
                        );
                      }

                      return ListView.builder(
                        controller: scrollController,
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final comment = comments[index];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundImage: comment['userProfileImage'] !=
                                          null &&
                                      comment['userProfileImage'].isNotEmpty
                                  ? NetworkImage(comment['userProfileImage'])
                                  : null,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: comment['userProfileImage'] == null ||
                                      comment['userProfileImage'].isEmpty
                                  ? Text(
                                      comment['username'] != null &&
                                              comment['username'].isNotEmpty
                                          ? comment['username'][0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            title: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                                children: [
                                  TextSpan(
                                    text:
                                        '${comment['username'] ?? 'Anonymous'} ',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(text: comment['text'] ?? ''),
                                ],
                              ),
                            ),
                            subtitle: comment['timestamp'] != null
                                ? Text(
                                    timeago.format(
                                        (comment['timestamp'] as Timestamp)
                                            .toDate()),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                          );
                        },
                      );
                    },
                  ),
                ),
                // Comment input field
                Padding(
                  padding: EdgeInsets.only(
                    left: 16.0,
                    right: 16.0,
                    top: 8.0,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 8.0,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: _feedService.currentUserId != null
                            ? NetworkImage(widget.post.userProfileImage)
                            : null,
                        child: _feedService.currentUserId == null
                            ? const Icon(Icons.person, size: 16)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: const InputDecoration(
                            hintText: 'Add a comment...',
                            border: InputBorder.none,
                          ),
                          maxLines: 1,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          if (_commentController.text.trim().isNotEmpty) {
                            _feedService.addComment(
                              widget.post.id,
                              _commentController.text.trim(),
                            );
                            _commentController.clear();
                          }
                        },
                        child: const Text('Post'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
