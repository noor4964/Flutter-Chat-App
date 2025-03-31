import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MessageBubble extends StatelessWidget {
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isMe;
  final bool isRead;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final MessageStatus status;
  final DateTime? seenTimestamp;

  const MessageBubble({
    super.key,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.isMe,
    required this.isRead,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.status = MessageStatus.sent,
    this.seenTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Facebook Messenger uses blue for sender's messages and light gray for receiver's messages
    final bubbleColor = isMe
        ? const Color(0xFF0084FF) // Messenger blue
        : theme.brightness == Brightness.dark
            ? const Color(0xFF3A3B3C) // Dark mode gray
            : const Color(0xFFE4E6EB); // Light mode gray

    final textColor = isMe || theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        // Apply different padding based on grouping
        padding: EdgeInsets.only(
          left: isMe ? 80.0 : 10.0, // Push sender's messages to right
          right: isMe ? 10.0 : 80.0, // Push receiver's messages to left
          top: isFirstInGroup ? 8.0 : 2.0,
          bottom: isLastInGroup ? 8.0 : 2.0,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            // Only show sender name for the first message in a group from the other person
            if (isFirstInGroup && !isMe)
              Padding(
                padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
                child: Text(
                  sender,
                  style: TextStyle(
                    fontSize: 12.0,
                    color: theme.brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Material(
              borderRadius: getBorderRadius(),
              elevation: 0.0, // Messenger uses flat bubbles
              color: bubbleColor,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                child: Column(
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      text,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16.0,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: isMe ? Colors.white70 : Colors.black38,
                            fontSize: 10.0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Show message status below the bubble for sender's messages
            if (isMe && isLastInGroup)
              Padding(
                padding: const EdgeInsets.only(top: 2.0, right: 4.0),
                child: _buildMessageStatus(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageStatus(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colorSubdued = theme.brightness == Brightness.dark
        ? Colors.grey[400]
        : Colors.grey[600];
    final colorBright = colorScheme.primary;

    if (!isMe) return const SizedBox.shrink();

    switch (status) {
      case MessageStatus.sending:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sending',
              style: TextStyle(
                color: colorSubdued,
                fontSize: 11.0,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colorSubdued,
              ),
            ),
          ],
        );
      case MessageStatus.sent:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check,
              color: colorSubdued,
              size: 14.0,
            ),
            const SizedBox(width: 4),
            Text(
              'Sent',
              style: TextStyle(
                color: colorSubdued,
                fontSize: 11.0,
              ),
            ),
          ],
        );
      case MessageStatus.seen:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.done_all,
                  color: colorBright,
                  size: 14.0,
                ),
                const SizedBox(width: 4),
                Text(
                  'Seen',
                  style: TextStyle(
                    color: colorBright,
                    fontSize: 11.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (seenTimestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 1.0, right: 2.0),
                child: Text(
                  _formatSeenTime(seenTimestamp!),
                  style: TextStyle(
                    color: colorSubdued,
                    fontSize: 10.0,
                  ),
                ),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String _formatSeenTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateTime = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (dateTime == today) {
      return 'Today at ${DateFormat('h:mm a').format(timestamp)}';
    } else if (dateTime == yesterday) {
      return 'Yesterday at ${DateFormat('h:mm a').format(timestamp)}';
    } else {
      return DateFormat('MMM d, h:mm a').format(timestamp);
    }
  }

  // Get appropriate border radius based on message position in the group
  BorderRadius getBorderRadius() {
    const double radius = 18.0;

    if (isMe) {
      if (isFirstInGroup && isLastInGroup) {
        // Single message
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius - 8),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius - 8),
        );
      } else if (isFirstInGroup) {
        // First message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius - 8),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(4),
        );
      } else if (isLastInGroup) {
        // Last message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius - 8),
          topRight: Radius.circular(4),
        );
      } else {
        // Middle message
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          bottomLeft: Radius.circular(radius),
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        );
      }
    } else {
      // Not me (other person's messages)
      if (isFirstInGroup && isLastInGroup) {
        // Single message
        return const BorderRadius.only(
          topLeft: Radius.circular(radius - 8),
          topRight: Radius.circular(radius),
          bottomLeft: Radius.circular(radius - 8),
          bottomRight: Radius.circular(radius),
        );
      } else if (isFirstInGroup) {
        // First message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius - 8),
          topRight: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
          bottomLeft: Radius.circular(4),
        );
      } else if (isLastInGroup) {
        // Last message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(radius - 8),
          bottomRight: Radius.circular(radius),
          topRight: Radius.circular(radius),
        );
      } else {
        // Middle message
        return const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
          topRight: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        );
      }
    }
  }
}

enum MessageStatus {
  sending,
  sent,
  seen,
}
