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

    return Padding(
      // Apply different padding based on grouping
      padding: EdgeInsets.only(
        left: 10.0,
        right: 10.0,
        top: isFirstInGroup ? 10.0 : 2.0,
        bottom: isLastInGroup ? 10.0 : 2.0,
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          // Only show sender name for the first message in a group
          if (isFirstInGroup)
            Text(
              sender,
              style: const TextStyle(
                fontSize: 12.0,
                color: Colors.black54,
              ),
            ),
          Material(
            borderRadius: getBorderRadius(),
            elevation: 1.0,
            color: isMe ? colorScheme.primary : Colors.white,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 15.0,
                    ),
                  ),
                  const SizedBox(height: 4.0),
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
                      const SizedBox(width: 2),
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
    if (isMe) {
      if (isFirstInGroup && isLastInGroup) {
        // Single message
        return const BorderRadius.only(
          topLeft: Radius.circular(18.0),
          bottomLeft: Radius.circular(18.0),
          bottomRight: Radius.circular(5.0),
          topRight: Radius.circular(18.0),
        );
      } else if (isFirstInGroup) {
        // First message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(18.0),
          bottomLeft: Radius.circular(18.0),
          bottomRight: Radius.circular(5.0),
          topRight: Radius.circular(18.0),
        );
      } else if (isLastInGroup) {
        // Last message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(18.0),
          bottomLeft: Radius.circular(18.0),
          bottomRight: Radius.circular(5.0),
          topRight: Radius.circular(5.0),
        );
      } else {
        // Middle message
        return const BorderRadius.only(
          topLeft: Radius.circular(18.0),
          bottomLeft: Radius.circular(18.0),
          bottomRight: Radius.circular(5.0),
          topRight: Radius.circular(5.0),
        );
      }
    } else {
      // Not me (other person's messages)
      if (isFirstInGroup && isLastInGroup) {
        // Single message
        return const BorderRadius.only(
          topLeft: Radius.circular(5.0),
          bottomLeft: Radius.circular(18.0),
          bottomRight: Radius.circular(18.0),
          topRight: Radius.circular(18.0),
        );
      } else if (isFirstInGroup) {
        // First message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(5.0),
          bottomLeft: Radius.circular(5.0),
          bottomRight: Radius.circular(18.0),
          topRight: Radius.circular(18.0),
        );
      } else if (isLastInGroup) {
        // Last message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(5.0),
          bottomLeft: Radius.circular(18.0),
          bottomRight: Radius.circular(18.0),
          topRight: Radius.circular(18.0),
        );
      } else {
        // Middle message
        return const BorderRadius.only(
          topLeft: Radius.circular(5.0),
          bottomLeft: Radius.circular(5.0),
          bottomRight: Radius.circular(18.0),
          topRight: Radius.circular(18.0),
        );
      }
    }
  }
}
