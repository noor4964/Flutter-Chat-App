import 'package:flutter/material.dart';
import 'package:flutter_chat_app/models/message_reaction.dart';

class MessageReactionPicker extends StatelessWidget {
  final Function(String emoji) onEmojiSelected;
  final VoidCallback onDismiss;

  const MessageReactionPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  // Common reaction emojis like WhatsApp/Telegram
  static const List<String> quickReactions = [
    '👍', '❤️', '😂', '😮', '😢', '🙏', '😡', '🤔'
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Transparent background to detect taps
          GestureDetector(
            onTap: onDismiss,
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          // Reaction picker
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: quickReactions.map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      onEmojiSelected(emoji);
                      onDismiss();
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageReactionDisplay extends StatelessWidget {
  final List<MessageReactionSummary> reactionSummaries;
  final Function(String emoji) onReactionTap;
  final String currentUserId;

  const MessageReactionDisplay({
    super.key,
    required this.reactionSummaries,
    required this.onReactionTap,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (reactionSummaries.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: reactionSummaries.map((summary) {
          final isUserReacted = summary.hasCurrentUserReacted;
          
          return GestureDetector(
            onTap: () => onReactionTap(summary.emoji),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isUserReacted
                    ? theme.colorScheme.primary.withOpacity(0.1)
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUserReacted
                      ? theme.colorScheme.primary.withOpacity(0.3)
                      : theme.colorScheme.outline.withOpacity(0.2),
                  width: isUserReacted ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    summary.emoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (summary.count > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      summary.count.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isUserReacted
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Reaction animation widget for when someone adds a reaction
class ReactionAnimation extends StatefulWidget {
  final String emoji;
  final VoidCallback onComplete;

  const ReactionAnimation({
    super.key,
    required this.emoji,
    required this.onComplete,
  });

  @override
  State<ReactionAnimation> createState() => _ReactionAnimationState();
}

class _ReactionAnimationState extends State<ReactionAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    ));

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
    ));

    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Text(
              widget.emoji,
              style: const TextStyle(fontSize: 32),
            ),
          ),
        );
      },
    );
  }
}