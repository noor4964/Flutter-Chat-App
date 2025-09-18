import 'package:flutter/material.dart';
import 'package:flutter_chat_app/models/message_reaction.dart';
import 'package:flutter_chat_app/widgets/message_reaction_widgets.dart';

class ModernMessageBubble extends StatelessWidget {
  final String message;
  final String time;
  final bool isMe;
  final bool isRead;
  final String bubbleStyle;
  final String? imageUrl;
  final Color primaryColor;
  final BorderRadius borderRadius;
  final List<MessageReaction> reactions;
  final Function(String emoji)? onReactionAdd;
  final VoidCallback? onLongPress;
  final String currentUserId;

  const ModernMessageBubble({
    Key? key,
    required this.message,
    required this.time,
    required this.isMe,
    this.isRead = false,
    this.bubbleStyle = 'Modern',
    this.imageUrl,
    required this.primaryColor,
    required this.borderRadius,
    this.reactions = const [],
    this.onReactionAdd,
    this.onLongPress,
    required this.currentUserId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Different background colors for sender and receiver
    final myBubbleColor =
        bubbleStyle == 'Minimal' ? primaryColor.withOpacity(0.9) : primaryColor;

    final otherBubbleColor = bubbleStyle == 'Minimal'
        ? (isDarkMode ? Colors.grey[800]! : Colors.grey[200]!)
        : (isDarkMode ? Colors.grey[700]! : Colors.grey[300]!);

    // Different text colors for sender and receiver
    final myTextColor = Colors.white;
    final otherTextColor = isDarkMode ? Colors.white : Colors.black87;

    // Build message content
    Widget messageContent;
    if (imageUrl != null) {
      // Image message
      messageContent = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl!,
          width: 200,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: 200,
              height: 200,
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  color: isMe ? Colors.white : primaryColor,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 200,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.red[400]),
                  const SizedBox(height: 4),
                  const Text(
                    'Image could not be loaded',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } else {
      // Text message
      messageContent = Text(
        message,
        style: TextStyle(
          color: isMe ? myTextColor : otherTextColor,
          fontSize: 16,
        ),
      );
    }

    // Apply different styles based on the selected bubble style
    switch (bubbleStyle) {
      case 'Rounded':
        return _buildRoundedBubble(
          context,
          messageContent,
          isMe ? myBubbleColor : otherBubbleColor,
          isMe ? myTextColor : otherTextColor,
        );

      case 'Minimal':
        return _buildMinimalBubble(
          context,
          messageContent,
          isMe ? myBubbleColor : otherBubbleColor,
          isMe ? myTextColor : otherTextColor,
        );

      case 'Chat GPT':
        return _buildChatGPTBubble(
          context,
          messageContent,
          isMe ? myBubbleColor : otherBubbleColor,
          isMe ? myTextColor : otherTextColor,
        );

      case 'Modern':
      default:
        return _buildModernBubble(
          context,
          messageContent,
          isMe ? myBubbleColor : otherBubbleColor,
          isMe ? myTextColor : otherTextColor,
        );
    }
  }

  Widget _buildModernBubble(BuildContext context, Widget messageContent,
      Color bubbleColor, Color textColor) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            child: GestureDetector(
              onLongPress: onLongPress,
              onSecondaryTap: onLongPress, // Right-click for web
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isMe ? borderRadius.topLeft.x : 4),
                    topRight: Radius.circular(isMe ? 4 : borderRadius.topRight.x),
                    bottomLeft: Radius.circular(borderRadius.bottomLeft.x),
                    bottomRight: Radius.circular(borderRadius.bottomRight.x),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    messageContent,
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          time,
                          style: TextStyle(
                            color: textColor.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 5),
                          Icon(
                            isRead ? Icons.done_all : Icons.done,
                            size: 14,
                            color: isRead ? Colors.green : textColor.withOpacity(0.7),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Reactions display
          if (reactions.isNotEmpty)
            MessageReactionDisplay(
              reactionSummaries: _getReactionSummaries(),
              onReactionTap: (emoji) {
                if (onReactionAdd != null) {
                  onReactionAdd!(emoji);
                }
              },
              currentUserId: currentUserId,
            ),
        ],
      ),
    );
  }

  Widget _buildRoundedBubble(BuildContext context, Widget messageContent,
      Color bubbleColor, Color textColor) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            child: GestureDetector(
              onLongPress: onLongPress,
              onSecondaryTap: onLongPress, // Web right-click support
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(borderRadius.topLeft.x),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    messageContent,
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          time,
                          style: TextStyle(
                            color: textColor.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 5),
                          Icon(
                            isRead ? Icons.done_all : Icons.done,
                            size: 14,
                            color: isRead ? Colors.green : textColor.withOpacity(0.7),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Reactions display
          if (reactions.isNotEmpty)
            MessageReactionDisplay(
              reactionSummaries: _getReactionSummaries(),
              onReactionTap: (emoji) {
                if (onReactionAdd != null) {
                  onReactionAdd!(emoji);
                }
              },
              currentUserId: currentUserId,
            ),
        ],
      ),
    );
  }

  Widget _buildMinimalBubble(BuildContext context, Widget messageContent,
      Color bubbleColor, Color textColor) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            child: GestureDetector(
              onLongPress: onLongPress,
              onSecondaryTap: onLongPress, // Web right-click support
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isMe ? borderRadius.topLeft.x : 0),
                    topRight: Radius.circular(isMe ? 0 : borderRadius.topRight.x),
                    bottomLeft: Radius.circular(borderRadius.bottomLeft.x),
                    bottomRight: Radius.circular(borderRadius.bottomRight.x),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    messageContent,
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          time,
                          style: TextStyle(
                            color: textColor.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 5),
                          Icon(
                            isRead ? Icons.done_all : Icons.done,
                            size: 14,
                            color: isRead ? Colors.green : textColor.withOpacity(0.7),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Reactions display
          if (reactions.isNotEmpty)
            MessageReactionDisplay(
              reactionSummaries: _getReactionSummaries(),
              onReactionTap: (emoji) {
                if (onReactionAdd != null) {
                  onReactionAdd!(emoji);
                }
              },
              currentUserId: currentUserId,
            ),
        ],
      ),
    );
  }

  Widget _buildChatGPTBubble(BuildContext context, Widget messageContent,
      Color bubbleColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              backgroundColor: bubbleColor,
              radius: 16,
              child: const Icon(Icons.person_outline,
                  size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              decoration: BoxDecoration(
                color: isMe ? bubbleColor : Colors.transparent,
                border: isMe
                    ? null
                    : Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
                borderRadius: BorderRadius.circular(borderRadius.topLeft.x),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  messageContent,
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        time,
                        style: TextStyle(
                          color: isMe
                              ? textColor.withOpacity(0.7)
                              : Colors.grey.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 5),
                        Icon(
                          isRead ? Icons.done_all : Icons.done,
                          size: 14,
                          color:
                              isRead ? Colors.green : textColor.withOpacity(0.7),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: bubbleColor,
              radius: 16,
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  List<MessageReactionSummary> _getReactionSummaries() {
    final Map<String, List<String>> reactionMap = {};
    
    for (final reaction in reactions) {
      if (reactionMap.containsKey(reaction.emoji)) {
        reactionMap[reaction.emoji]!.add(reaction.userId);
      } else {
        reactionMap[reaction.emoji] = [reaction.userId];
      }
    }

    return reactionMap.entries.map((entry) {
      return MessageReactionSummary(
        emoji: entry.key,
        count: entry.value.length,
        userIds: entry.value,
        hasCurrentUserReacted: entry.value.contains(currentUserId),
      );
    }).toList();
  }
}
