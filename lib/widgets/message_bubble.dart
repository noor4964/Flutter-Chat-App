import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isMe;
  final bool isRead;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const MessageBubble({
    super.key,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.isMe,
    required this.isRead,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
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

    return Padding(
      // Apply different padding based on grouping
      padding: EdgeInsets.only(
        left: isMe
            ? 60.0
            : 10.0, // More space on left for sender's messages (push to right)
        right: isMe
            ? 10.0
            : 60.0, // More space on right for receiver's messages (push to left)
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
                      const SizedBox(width: 4),
                      if (isMe && isRead)
                        const Icon(
                          Icons.done_all,
                          color: Colors.white70,
                          size: 12.0,
                        ),
                      if (isMe && !isRead)
                        const Icon(
                          Icons.done,
                          color: Colors.white70,
                          size: 12.0,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Get appropriate border radius based on message position in the group
  BorderRadius getBorderRadius() {
    const double radius = 18.0;

    if (isMe) {
      if (isFirstInGroup && isLastInGroup) {
        // Single message
        return const BorderRadius.all(Radius.circular(radius));
      } else if (isFirstInGroup) {
        // First message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius / 3),
        );
      } else if (isLastInGroup) {
        // Last message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
          topRight: Radius.circular(radius / 3),
        );
      } else {
        // Middle message
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          bottomLeft: Radius.circular(radius),
          topRight: Radius.circular(radius / 3),
          bottomRight: Radius.circular(radius / 3),
        );
      }
    } else {
      // Not me (other person's messages)
      if (isFirstInGroup && isLastInGroup) {
        // Single message
        return const BorderRadius.all(Radius.circular(radius));
      } else if (isFirstInGroup) {
        // First message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
          bottomLeft: Radius.circular(radius / 3),
        );
      } else if (isLastInGroup) {
        // Last message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius / 3),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
          topRight: Radius.circular(radius),
        );
      } else {
        // Middle message
        return const BorderRadius.only(
          topLeft: Radius.circular(radius / 3),
          bottomLeft: Radius.circular(radius / 3),
          topRight: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        );
      }
    }
  }
}
