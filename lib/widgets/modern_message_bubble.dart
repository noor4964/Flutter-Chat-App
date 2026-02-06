import 'package:flutter/material.dart';
import 'package:flutter_chat_app/models/message_reaction.dart';
import 'package:flutter_chat_app/widgets/message_reaction_widgets.dart';

/// Helper class to compute bubble colors with modern gradient support.
class _BubbleColors {
  final Color bubble;
  final Color bubbleEnd; // gradient end color for sender
  final Color text;
  final Color meta; // timestamps & read-receipts

  const _BubbleColors({
    required this.bubble,
    required this.bubbleEnd,
    required this.text,
    required this.meta,
  });

  /// Sender (isMe) bubble: primary → slightly hue-shifted primary.
  factory _BubbleColors.sender(Color primaryColor, String bubbleStyle) {
    final hsl = HSLColor.fromColor(primaryColor);
    final endColor = hsl
        .withHue((hsl.hue + 18) % 360)
        .withLightness((hsl.lightness - 0.06).clamp(0.0, 1.0))
        .toColor();
    return _BubbleColors(
      bubble: bubbleStyle == 'Minimal'
          ? primaryColor.withOpacity(0.92)
          : primaryColor,
      bubbleEnd: endColor,
      text: Colors.white,
      meta: Colors.white.withOpacity(0.75),
    );
  }

  /// Receiver (other) bubble: surface container tones.
  factory _BubbleColors.receiver(bool isDark, String bubbleStyle) {
    return _BubbleColors(
      bubble: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF0F0F3),
      bubbleEnd: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF0F0F3),
      text: isDark ? Colors.white : const Color(0xFF1A1A1A),
      meta: isDark
          ? Colors.white.withOpacity(0.5)
          : const Color(0xFF1A1A1A).withOpacity(0.45),
    );
  }
}

class ModernMessageBubble extends StatelessWidget {
  final String message;
  final String time;
  final bool isMe;
  final bool isRead;
  final String bubbleStyle;
  final String? imageUrl;
  final String messageType;
  final Map<String, dynamic>? messageData;
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
    this.messageType = 'text',
    this.messageData,
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

    final colors = isMe
        ? _BubbleColors.sender(primaryColor, bubbleStyle)
        : _BubbleColors.receiver(isDarkMode, bubbleStyle);

    // Build message content based on type
    Widget messageContent;
    switch (messageType) {
      case 'image':
        messageContent = _buildImageMessage(context, colors);
        break;
      case 'document':
        messageContent = _buildDocumentMessage(context, colors);
        break;
      case 'location':
        messageContent = _buildLocationMessage(context, colors);
        break;
      case 'text':
      default:
        messageContent = _buildTextMessage(colors);
        break;
    }

    // Apply different styles based on the selected bubble style
    switch (bubbleStyle) {
      case 'Rounded':
        return _buildRoundedBubble(context, messageContent, colors);

      case 'Minimal':
        return _buildMinimalBubble(context, messageContent, colors);

      case 'Chat GPT':
        return _buildChatGPTBubble(context, messageContent, colors);

      case 'Modern':
      default:
        return _buildModernBubble(context, messageContent, colors);
    }
  }

  // ────────────────────────────────────────────────────────────
  //  Time & read-receipt row (shared by all styles)
  // ────────────────────────────────────────────────────────────
  Widget _buildTimeRow(_BubbleColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          time,
          style: TextStyle(
            color: colors.meta,
            fontSize: 11,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.1,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          Icon(
            isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 15,
            color: isRead
                ? const Color(0xFF4FC3F7) // modern blue read ticks
                : colors.meta,
          ),
        ],
      ],
    );
  }

  // ────────────────────────────────────────────────────────────
  //  iMessage-style adaptive corner radii
  // ────────────────────────────────────────────────────────────
  BorderRadius _modernCorners() {
    const big = Radius.circular(20);
    const small = Radius.circular(6);
    return BorderRadius.only(
      topLeft: isMe ? big : small,
      topRight: isMe ? small : big,
      bottomLeft: big,
      bottomRight: big,
    );
  }

  // ────────────────────────────────────────────────────────────
  //  Modern bubble (gradient sender, colored shadow)
  // ────────────────────────────────────────────────────────────
  Widget _buildModernBubble(
      BuildContext context, Widget messageContent, _BubbleColors colors) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: GestureDetector(
              onLongPress: onLongPress,
              onSecondaryTap: onLongPress,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3.0),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14.0, vertical: 10.0),
                decoration: BoxDecoration(
                  gradient: isMe
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colors.bubble, colors.bubbleEnd],
                        )
                      : null,
                  color: isMe ? null : colors.bubble,
                  borderRadius: _modernCorners(),
                  boxShadow: [
                    BoxShadow(
                      color: isMe
                          ? primaryColor.withOpacity(0.25)
                          : Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    messageContent,
                    const SizedBox(height: 4),
                    _buildTimeRow(colors),
                  ],
                ),
              ),
            ),
          ),
          if (reactions.isNotEmpty)
            MessageReactionDisplay(
              reactionSummaries: _getReactionSummaries(),
              onReactionTap: (emoji) => onReactionAdd?.call(emoji),
              currentUserId: currentUserId,
            ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  Rounded bubble
  // ────────────────────────────────────────────────────────────
  Widget _buildRoundedBubble(
      BuildContext context, Widget messageContent, _BubbleColors colors) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: GestureDetector(
              onLongPress: onLongPress,
              onSecondaryTap: onLongPress,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3.0),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14.0, vertical: 10.0),
                decoration: BoxDecoration(
                  gradient: isMe
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colors.bubble, colors.bubbleEnd],
                        )
                      : null,
                  color: isMe ? null : colors.bubble,
                  borderRadius:
                      BorderRadius.circular(borderRadius.topLeft.x),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    messageContent,
                    const SizedBox(height: 4),
                    _buildTimeRow(colors),
                  ],
                ),
              ),
            ),
          ),
          if (reactions.isNotEmpty)
            MessageReactionDisplay(
              reactionSummaries: _getReactionSummaries(),
              onReactionTap: (emoji) => onReactionAdd?.call(emoji),
              currentUserId: currentUserId,
            ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  Minimal bubble
  // ────────────────────────────────────────────────────────────
  Widget _buildMinimalBubble(
      BuildContext context, Widget messageContent, _BubbleColors colors) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: GestureDetector(
              onLongPress: onLongPress,
              onSecondaryTap: onLongPress,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3.0),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: colors.bubble,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(
                        isMe ? borderRadius.topLeft.x : 0),
                    topRight: Radius.circular(
                        isMe ? 0 : borderRadius.topRight.x),
                    bottomLeft:
                        Radius.circular(borderRadius.bottomLeft.x),
                    bottomRight:
                        Radius.circular(borderRadius.bottomRight.x),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    messageContent,
                    const SizedBox(height: 4),
                    _buildTimeRow(colors),
                  ],
                ),
              ),
            ),
          ),
          if (reactions.isNotEmpty)
            MessageReactionDisplay(
              reactionSummaries: _getReactionSummaries(),
              onReactionTap: (emoji) => onReactionAdd?.call(emoji),
              currentUserId: currentUserId,
            ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  Chat GPT bubble (avatar + border for receiver)
  // ────────────────────────────────────────────────────────────
  Widget _buildChatGPTBubble(
      BuildContext context, Widget messageContent, _BubbleColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              backgroundColor: colors.bubble,
              radius: 16,
              child: Icon(Icons.person_outline,
                  size: 18, color: colors.text),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14.0, vertical: 10.0),
              decoration: BoxDecoration(
                gradient: isMe
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors.bubble, colors.bubbleEnd],
                      )
                    : null,
                color: isMe ? null : Colors.transparent,
                border: isMe
                    ? null
                    : Border.all(
                        color: Colors.grey.withOpacity(0.25), width: 1),
                borderRadius:
                    BorderRadius.circular(borderRadius.topLeft.x),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  messageContent,
                  const SizedBox(height: 4),
                  _buildTimeRow(colors),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: colors.bubble,
              radius: 16,
              child:
                  Icon(Icons.person, size: 18, color: colors.text),
            ),
          ],
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  Reaction helpers
  // ────────────────────────────────────────────────────────────
  List<MessageReactionSummary> _getReactionSummaries() {
    final Map<String, List<String>> reactionMap = {};
    for (final reaction in reactions) {
      reactionMap.putIfAbsent(reaction.emoji, () => []).add(reaction.userId);
    }
    return reactionMap.entries
        .map((e) => MessageReactionSummary(
              emoji: e.key,
              count: e.value.length,
              userIds: e.value,
              hasCurrentUserReacted: e.value.contains(currentUserId),
            ))
        .toList();
  }

  // ────────────────────────────────────────────────────────────
  //  TEXT message
  // ────────────────────────────────────────────────────────────
  Widget _buildTextMessage(_BubbleColors colors) {
    return Text(
      message,
      style: TextStyle(
        color: colors.text,
        fontSize: 15.5,
        height: 1.35,
        letterSpacing: 0.1,
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  IMAGE message
  // ────────────────────────────────────────────────────────────
  Widget _buildImageMessage(BuildContext context, _BubbleColors colors) {
    final uploadStatus = messageData?['uploadStatus'] ?? 'completed';
    final uploadProgress = messageData?['uploadProgress'] ?? 100.0;
    final hasValidUrl = imageUrl != null && imageUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              if (hasValidUrl && uploadStatus == 'completed')
                Image.network(
                  imageUrl!,
                  width: 220,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: 220,
                      height: 200,
                      decoration: BoxDecoration(
                        color: colors.bubble.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          color: isMe ? Colors.white70 : primaryColor,
                          strokeWidth: 2.5,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) =>
                      _buildImageErrorWidget(),
                )
              else
                _buildImagePlaceholder(uploadStatus, uploadProgress),

              // Upload progress overlay
              if (uploadStatus == 'uploading')
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: uploadProgress / 100.0,
                            color: Colors.white,
                            backgroundColor: Colors.white.withOpacity(0.25),
                            strokeWidth: 2.5,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${uploadProgress.toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Failed upload indicator
              if (uploadStatus == 'failed')
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red[300], size: 32),
                          const SizedBox(height: 4),
                          const Text('Upload failed',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12)),
                          const SizedBox(height: 4),
                          const Text('Tap to retry',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (message.isNotEmpty && !message.startsWith('http'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              message,
              style: TextStyle(
                color: colors.text,
                fontSize: 15.5,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImagePlaceholder(String uploadStatus, double uploadProgress) {
    return Container(
      width: 220,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.image_rounded, size: 48, color: Colors.grey),
      ),
    );
  }

  Widget _buildImageErrorWidget() {
    return Container(
      width: 220,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_rounded, color: Colors.red[300], size: 28),
          const SizedBox(height: 4),
          Text(
            'Image could not be loaded',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  DOCUMENT message
  // ────────────────────────────────────────────────────────────
  Widget _buildDocumentMessage(BuildContext context, _BubbleColors colors) {
    final fileName = messageData?['fileName'] ?? 'Document';
    final fileSize = messageData?['fileSize'] ?? 0;
    final fileSizeStr = _formatFileSize(fileSize);
    final uploadStatus = messageData?['uploadStatus'] ?? 'completed';
    final uploadProgress = messageData?['uploadProgress'] ?? 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.white.withOpacity(0.12)
                : Colors.grey.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modern rounded-square document icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white.withOpacity(0.18)
                      : primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.insert_drive_file_rounded,
                      color: isMe ? colors.text : primaryColor,
                      size: 22,
                    ),
                    if (uploadStatus == 'uploading')
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          value: uploadProgress / 100.0,
                          strokeWidth: 2,
                          color: isMe ? colors.text : primaryColor,
                          backgroundColor:
                              (isMe ? colors.text : primaryColor)
                                  .withOpacity(0.25),
                        ),
                      ),
                    if (uploadStatus == 'failed')
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 1),
                          ),
                          child: const Icon(Icons.error,
                              size: 9, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (fileSize > 0)
                          Text(fileSizeStr,
                              style: TextStyle(
                                  color: colors.meta, fontSize: 12)),
                        if (uploadStatus == 'uploading') ...[
                          if (fileSize > 0)
                            Text(' · ',
                                style: TextStyle(
                                    color: colors.meta, fontSize: 12)),
                          Text('Uploading ${uploadProgress.toInt()}%',
                              style: TextStyle(
                                  color: colors.meta, fontSize: 12)),
                        ],
                        if (uploadStatus == 'failed') ...[
                          if (fileSize > 0)
                            Text(' · ',
                                style: TextStyle(
                                    color: colors.meta, fontSize: 12)),
                          Text('Failed · Tap to retry',
                              style: TextStyle(
                                  color: Colors.red[300], fontSize: 12)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (message.isNotEmpty && message != fileName)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              message,
              style: TextStyle(
                color: colors.text,
                fontSize: 15.5,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────
  //  LOCATION message
  // ────────────────────────────────────────────────────────────
  Widget _buildLocationMessage(BuildContext context, _BubbleColors colors) {
    final latitude = messageData?['latitude'] ?? 0.0;
    final longitude = messageData?['longitude'] ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.white.withOpacity(0.12)
                : Colors.grey.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modern rounded-square location icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white.withOpacity(0.18)
                      : Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: isMe ? colors.text : Colors.red[400],
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shared Location',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
                      style: TextStyle(
                        color: colors.meta,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (message.isNotEmpty && !message.startsWith('Location:'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              message,
              style: TextStyle(
                color: colors.text,
                fontSize: 15.5,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────
  //  Utility
  // ────────────────────────────────────────────────────────────

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[i]}';
  }
}
