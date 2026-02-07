import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_chat_app/providers/call_provider.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';
import 'package:flutter_chat_app/views/calls/audio_call_screen.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({Key? key}) : super(key: key);

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CallProvider>(context, listen: false).loadCallHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call History'),
        backgroundColor: theme.brightness == Brightness.dark
            ? colorScheme.surface
            : colorScheme.primary,
        foregroundColor:
            theme.brightness == Brightness.dark ? null : Colors.white,
      ),
      body: Consumer<CallProvider>(
        builder: (context, callProvider, child) {
          if (callProvider.isLoadingHistory) {
            return const Center(child: CircularProgressIndicator());
          }

          if (callProvider.callHistory.isEmpty) {
            return _buildEmptyState();
          }

          return RefreshIndicator(
            onRefresh: () => callProvider.loadCallHistory(),
            child: ListView.builder(
              itemCount: callProvider.callHistory.length,
              itemBuilder: (context, index) {
                final call = callProvider.callHistory[index];
                return _buildCallItem(context, call, callProvider);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.call_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No call history',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Your recent calls will appear here',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCallItem(
      BuildContext context, Call call, CallProvider callProvider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUser = FirebaseAuth.instance.currentUser;
    final bool isOutgoing = currentUser?.uid == call.callerId;
    final bool isMissed =
        call.status == 'missed' && call.missedBy == currentUser?.uid;

    final String contactName =
        isOutgoing ? call.receiverName : call.callerName;
    final String? contactPhoto =
        isOutgoing ? call.receiverPhotoUrl : call.callerPhotoUrl;
    final String contactId = isOutgoing ? call.receiverId : call.callerId;

    // Direction icon
    IconData directionIcon;
    Color directionColor;
    if (isMissed) {
      directionIcon = Icons.call_missed;
      directionColor = Colors.red;
    } else if (call.status == 'declined') {
      directionIcon = isOutgoing ? Icons.call_made : Icons.call_missed;
      directionColor = Colors.red;
    } else if (isOutgoing) {
      directionIcon = Icons.call_made;
      directionColor = Colors.green;
    } else {
      directionIcon = Icons.call_received;
      directionColor = Colors.green;
    }

    // Duration text
    String subtitle;
    if (call.duration != null && call.duration! > 0) {
      final mins = call.duration! ~/ 60;
      final secs = call.duration! % 60;
      subtitle = '${mins}m ${secs}s';
    } else if (isMissed) {
      subtitle = 'Missed';
    } else if (call.status == 'declined') {
      subtitle = 'Declined';
    } else {
      subtitle = call.status;
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: colorScheme.primary.withOpacity(0.1),
        backgroundImage:
            contactPhoto != null ? NetworkImage(contactPhoto) : null,
        child: contactPhoto == null
            ? Text(
                contactName.isNotEmpty ? contactName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              )
            : null,
      ),
      title: Text(
        contactName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isMissed ? Colors.red : null,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(directionIcon, size: 16, color: directionColor),
          const SizedBox(width: 4),
          Text(subtitle),
          const SizedBox(width: 8),
          Text(
            timeago.format(call.timestamp),
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (call.isVideo)
            Icon(Icons.videocam, size: 18, color: Colors.grey[500]),
          if (!call.isVideo)
            Icon(Icons.call, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 8),
          // Call-back button
          IconButton(
            icon: Icon(
              call.isVideo ? Icons.videocam : Icons.call,
              color: colorScheme.primary,
            ),
            onPressed: () => _callBack(context, callProvider, contactId, call.isVideo),
            tooltip: 'Call back',
          ),
        ],
      ),
    );
  }

  Future<void> _callBack(
    BuildContext context,
    CallProvider callProvider,
    String contactId,
    bool isVideo,
  ) async {
    final call = await callProvider.startCall(contactId, isVideo);
    if (call != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudioCallScreen(call: call, isIncoming: false),
        ),
      );
    }
  }
}
