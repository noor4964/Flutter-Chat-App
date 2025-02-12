import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            sender,
            style: TextStyle(
              fontSize: 12.0,
              color: Colors.black54,
            ),
          ),
          Material(
            borderRadius: isMe
                ? const BorderRadius.only(
                    topLeft: Radius.circular(30.0),
                    bottomLeft: Radius.circular(30.0),
                    bottomRight: Radius.circular(30.0),
                  )
                : const BorderRadius.only(
                    topRight: Radius.circular(30.0),
                    bottomLeft: Radius.circular(30.0),
                    bottomRight: Radius.circular(30.0),
                  ),
            elevation: 5.0,
            color: isMe ? Colors.blueAccent : Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black54,
                      fontSize: 15.0,
                    ),
                  ),
                  const SizedBox(height: 5.0),
                  Text(
                    '${timestamp.hour}:${timestamp.minute}',
                    style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.black38,
                      fontSize: 10.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

