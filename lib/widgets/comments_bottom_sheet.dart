import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/models/comment_model.dart';
import 'package:flutter_chat_app/providers/feed_provider.dart';
import 'package:flutter_chat_app/services/post_service.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Opens a draggable bottom sheet showing real-time comments for a post.
///
/// Usage:
/// ```dart
/// CommentsBottomSheet.show(context, postId: post.id);
/// ```
class CommentsBottomSheet extends StatefulWidget {
  final String postId;

  const CommentsBottomSheet({Key? key, required this.postId}) : super(key: key);

  /// Convenience method to present the sheet.
  static void show(BuildContext context, {required String postId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsBottomSheet(postId: postId),
    );
  }

  @override
  State<CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<CommentsBottomSheet> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PostService _postService = PostService();
  bool _isSending = false;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                // ── Drag handle + title ──────────────────────────────
                _buildHeader(theme),

                // ── Comments list ─────────────────────────────────────
                Expanded(
                  child: StreamBuilder<List<Comment>>(
                    stream: _postService.getComments(widget.postId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }

                      final comments = snapshot.data ?? [];

                      if (comments.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No comments yet',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Be the first to comment!',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          return _CommentTile(
                            comment: comments[index],
                            postId: widget.postId,
                          );
                        },
                      );
                    },
                  ),
                ),

                // ── Input bar ─────────────────────────────────────────
                _buildInputBar(theme, isDark, bottomInset),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Comments',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Divider(
          height: 1,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.10)
              : Colors.black.withOpacity(0.08),
        ),
      ],
    );
  }

  Widget _buildInputBar(ThemeData theme, bool isDark, double bottomInset) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: 8 + bottomInset,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.08),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // User avatar
            CircleAvatar(
              radius: 16,
              backgroundImage: currentUser?.photoURL != null
                  ? NetworkImage(currentUser!.photoURL!)
                  : null,
              child: currentUser?.photoURL == null
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            const SizedBox(width: 8),

            // Text field
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                minLines: 1,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor:
                      isDark ? const Color(0xFF1E1E1E) : Colors.grey[200],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Send button
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _textController,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return IconButton(
                  onPressed: hasText && !_isSending ? _sendComment : null,
                  icon: Icon(
                    Icons.send_rounded,
                    color: hasText
                        ? theme.colorScheme.primary
                        : Colors.grey[400],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _textController.clear();

    try {
      final feedProvider = Provider.of<FeedProvider>(context, listen: false);
      await feedProvider.addComment(widget.postId, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post comment: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _focusNode.requestFocus();
      }
    }
  }
}

// ── Individual Comment Tile ───────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final String postId;

  const _CommentTile({
    Key? key,
    required this.comment,
    required this.postId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwnComment = currentUser?.uid == comment.userId;
    final isLiked = currentUser != null && comment.isLikedBy(currentUser.uid);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 16,
            backgroundImage: comment.userProfileImage.isNotEmpty
                ? NetworkImage(comment.userProfileImage)
                : null,
            child: comment.userProfileImage.isEmpty
                ? Text(
                    comment.username.isNotEmpty ? comment.username[0] : 'U',
                    style: const TextStyle(fontSize: 12),
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // Comment body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Username + text
                RichText(
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      TextSpan(
                        text: comment.username,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: '  '),
                      TextSpan(text: comment.text),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // Timestamp + like + reply + delete
                Row(
                  children: [
                    Text(
                      timeago.format(comment.timestamp, locale: 'en_short'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Like count
                    if (comment.likeCount > 0) ...[
                      Text(
                        '${comment.likeCount} ${comment.likeCount == 1 ? 'like' : 'likes'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],

                    // Delete (own comments)
                    if (isOwnComment)
                      GestureDetector(
                        onTap: () => _deleteComment(context),
                        child: Text(
                          'Delete',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red[400],
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Like button
          GestureDetector(
            onTap: () => _toggleLike(context),
            child: Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                size: 14,
                color: isLiked ? Colors.red : Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleLike(BuildContext context) {
    final postService = PostService();
    postService.toggleCommentLike(postId, comment.id);
  }

  void _deleteComment(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final feedProvider =
                  Provider.of<FeedProvider>(context, listen: false);
              feedProvider.deleteComment(postId, comment.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
