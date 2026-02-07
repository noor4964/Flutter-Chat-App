import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_chat_app/providers/call_provider.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';

class AudioCallScreen extends StatefulWidget {
  final Call call;
  final bool isIncoming;

  const AudioCallScreen({
    Key? key,
    required this.call,
    this.isIncoming = false,
  }) : super(key: key);

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rippleController;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _rippleController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUser = FirebaseAuth.instance.currentUser;
    final bool isCurrentUserCaller = currentUser?.uid == widget.call.callerId;

    final String otherPersonName =
        isCurrentUserCaller ? widget.call.receiverName : widget.call.callerName;
    final String? otherPersonPhotoUrl = isCurrentUserCaller
        ? widget.call.receiverPhotoUrl
        : widget.call.callerPhotoUrl;

    return Consumer<CallProvider>(
      builder: (context, callProvider, child) {
        // Auto-exit when call reaches a terminal state
        if (!_isExiting &&
            (callProvider.callState == CallState.ended ||
                callProvider.callState == CallState.declined ||
                callProvider.callState == CallState.missed)) {
          _isExiting = true;
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop();
          });
        }

        final bool isConnected = callProvider.callState == CallState.connected;
        final String statusText = _getStatusText(callProvider);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (isConnected) {
              _showExitConfirmation(context, callProvider);
            } else {
              callProvider.endCall();
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  if (isConnected) {
                    _showExitConfirmation(context, callProvider);
                  } else {
                    callProvider.endCall();
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colorScheme.primary.withOpacity(0.85),
                    colorScheme.primaryContainer.withOpacity(0.65),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 1),

                    // Avatar with ripple animation
                    _buildAvatar(
                      otherPersonName,
                      otherPersonPhotoUrl,
                      isConnected,
                      colorScheme,
                    ),

                    const SizedBox(height: 24),

                    // Name
                    Text(
                      otherPersonName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Status / Duration
                    Text(
                      isConnected
                          ? callProvider.formattedDuration
                          : statusText,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Controls
                    _buildControls(context, callProvider, isConnected, colorScheme),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _getStatusText(CallProvider provider) {
    switch (provider.callState) {
      case CallState.idle:
        return 'Initializing...';
      case CallState.ringing:
        return widget.isIncoming ? 'Incoming call...' : 'Calling...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return provider.formattedDuration;
      case CallState.ended:
        return 'Call ended';
      case CallState.declined:
        return 'Call declined';
      case CallState.missed:
        return 'Call missed';
      case CallState.error:
        return 'Call failed';
    }
  }

  Widget _buildAvatar(
    String name,
    String? photoUrl,
    bool isConnected,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple rings
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _rippleController,
              builder: (context, child) {
                final double size =
                    150 + (index * 30) + (_rippleController.value * 40);
                final double opacity =
                    (1 - _rippleController.value - (index * 0.1))
                        .clamp(0.0, 1.0);
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? Colors.green.withOpacity(opacity * 0.3)
                        : Colors.blue.withOpacity(opacity * 0.3),
                  ),
                );
              },
            );
          }),

          // Avatar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.2),
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: colorScheme.primary.withOpacity(0.2),
              backgroundImage:
                  photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    CallProvider callProvider,
    bool isConnected,
    ColorScheme colorScheme,
  ) {
    // Incoming call: show Answer + Decline
    if (widget.isIncoming &&
        callProvider.callState == CallState.ringing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildControlButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            label: 'Decline',
            onPressed: () {
              callProvider.endCall(isDeclined: true);
              if (mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 48),
          _buildControlButton(
            icon: Icons.call,
            backgroundColor: Colors.green,
            label: 'Answer',
            onPressed: () => callProvider.answerCall(widget.call.callId),
          ),
        ],
      );
    }

    // Outgoing ringing / connected: show Mute, End, Speaker
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildControlButton(
          icon: callProvider.isMuted ? Icons.mic_off : Icons.mic,
          backgroundColor: callProvider.isMuted
              ? Colors.white.withOpacity(0.3)
              : Colors.white.withOpacity(0.2),
          iconColor: callProvider.isMuted ? Colors.red : Colors.white,
          label: 'Mute',
          onPressed: isConnected ? () => callProvider.toggleMute() : null,
        ),
        const SizedBox(width: 24),
        _buildControlButton(
          icon: Icons.call_end,
          backgroundColor: Colors.red,
          size: 70,
          iconSize: 32,
          label: 'End',
          onPressed: () {
            callProvider.endCall();
            if (mounted) Navigator.of(context).pop();
          },
        ),
        const SizedBox(width: 24),
        _buildControlButton(
          icon: callProvider.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
          backgroundColor: callProvider.isSpeakerOn
              ? Colors.white.withOpacity(0.3)
              : Colors.white.withOpacity(0.2),
          iconColor:
              callProvider.isSpeakerOn ? colorScheme.primary : Colors.white,
          label: 'Speaker',
          onPressed: isConnected ? () => callProvider.toggleSpeaker() : null,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color backgroundColor,
    Color? iconColor,
    required String label,
    VoidCallback? onPressed,
    double size = 60,
    double iconSize = 28,
  }) {
    return Column(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: FloatingActionButton(
            heroTag: label,
            backgroundColor: backgroundColor,
            onPressed: onPressed,
            elevation: 8,
            child: Icon(icon, color: iconColor ?? Colors.white, size: iconSize),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  void _showExitConfirmation(BuildContext context, CallProvider callProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Call'),
        content: const Text('Are you sure you want to end the call?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              callProvider.endCall();
              Navigator.of(context).pop();
            },
            child: const Text('End Call'),
          ),
        ],
      ),
    );
  }
}
