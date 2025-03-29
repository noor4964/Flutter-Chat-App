import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class AudioCallScreen extends StatefulWidget {
  final Call call;
  final bool isIncoming;

  const AudioCallScreen({
    Key? key,
    required this.call,
    this.isIncoming = false,
  }) : super(key: key);

  @override
  _AudioCallScreenState createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen>
    with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  bool _isCallConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCallEnding = false;
  String _callStatus = 'Connecting...';
  String _callDuration = '00:00';
  Timer? _callTimer;

  // Animation controller for the ripple effect
  late AnimationController _rippleController;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Initialize the call service and listen for call status changes
    _initialize();

    // Disable screen timeout during call
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);

    // Keep screen on during call
    Wakelock.enable();
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _callTimer?.cancel();
    Wakelock.disable();
    super.dispose();
  }

  // Initialize call service and listen for call status changes
  Future<void> _initialize() async {
    try {
      // Listen for call status changes
      _callService
          .listenForCallStatusChanges(widget.call.callId)
          .listen(_handleCallStatusChanged, onError: _handleCallError);

      if (widget.isIncoming && widget.call.status == 'ringing') {
        setState(() {
          _callStatus = 'Incoming call...';
        });
      } else if (!widget.isIncoming && widget.call.status == 'ringing') {
        setState(() {
          _callStatus = 'Calling...';
        });
      } else if (widget.call.status == 'ongoing') {
        _handleCallConnected();
      }
    } catch (e) {
      print('Error initializing call: $e');
      _showError('Failed to initialize call');
    }
  }

  // Handle call status changes
  void _handleCallStatusChanged(Call call) {
    if (call.status == 'ongoing' && !_isCallConnected) {
      _handleCallConnected();
    } else if (call.status == 'ended' || call.status == 'declined') {
      _handleCallEnded(call.status == 'declined');
    }
  }

  // Handle call connection
  void _handleCallConnected() {
    if (!mounted) return;

    setState(() {
      _isCallConnected = true;
      _callStatus = 'Connected';

      // Vibrate to indicate call connected
      HapticFeedback.mediumImpact();

      // Start the call timer
      _startCallTimer();
    });
  }

  // Start the call duration timer
  void _startCallTimer() {
    int seconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      seconds++;
      setState(() {
        int minutes = seconds ~/ 60;
        int remainingSeconds = seconds % 60;
        _callDuration =
            '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
      });
    });
  }

  // Handle call ending
  void _handleCallEnded(bool isDeclined) {
    if (!mounted || _isCallEnding) return;

    _isCallEnding = true;
    _callTimer?.cancel();

    // Add haptic feedback
    HapticFeedback.mediumImpact();

    setState(() {
      _callStatus = isDeclined ? 'Call declined' : 'Call ended';
    });

    // Close the screen after a delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  // Handle call errors
  void _handleCallError(dynamic error) {
    print('Call error: $error');
    _showError('Call connection error');

    // End the call and close the screen
    _callService.endCall();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  // Show error message
  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _callStatus = message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.red,
      ),
    );
  }

  // Toggle mute status
  Future<void> _toggleMute() async {
    bool isMuted = await _callService.toggleMute();

    if (mounted) {
      setState(() {
        _isMuted = isMuted;
      });
    }
  }

  // Toggle speaker mode
  Future<void> _toggleSpeaker() async {
    bool isSpeakerOn = await _callService.toggleSpeaker();

    if (mounted) {
      setState(() {
        _isSpeakerOn = isSpeakerOn;
      });
    }
  }

  // End the call
  Future<void> _endCall() async {
    if (_isCallEnding) return;

    setState(() {
      _isCallEnding = true;
      _callStatus = 'Ending call...';
    });

    await _callService.endCall();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // Answer an incoming call
  Future<void> _answerCall() async {
    try {
      setState(() {
        _callStatus = 'Connecting...';
      });

      bool success = await _callService.answerCall(widget.call.callId);

      if (!success && mounted) {
        _showError('Failed to answer call');
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.of(context).pop();
        });
      }
    } catch (e) {
      print('Error answering call: $e');
      _showError('Failed to answer call');
    }
  }

  // Decline an incoming call
  Future<void> _declineCall() async {
    try {
      setState(() {
        _isCallEnding = true;
        _callStatus = 'Declining call...';
      });

      await _callService.endCall(isDeclined: true);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error declining call: $e');
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isCurrentUserCaller = _currentUser?.uid == widget.call.callerId;

    // Get the user details based on whether current user is caller or receiver
    final String otherPersonName =
        isCurrentUserCaller ? widget.call.receiverName : widget.call.callerName;

    final String? otherPersonPhotoUrl = isCurrentUserCaller
        ? widget.call.receiverPhotoUrl
        : widget.call.callerPhotoUrl;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        // Handle back button press
        _showExitConfirmationDialog();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_isCallConnected) {
                _endCall();
              } else {
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
                colorScheme.primary.withOpacity(0.8),
                colorScheme.primaryContainer.withOpacity(0.6),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 1),

                // User avatar with ripple effect
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Multiple ripple effects
                      ...List.generate(3, (index) {
                        return AnimatedBuilder(
                          animation: _rippleController,
                          builder: (context, child) {
                            final double rippleSize = 150 +
                                (index * 30) +
                                (_rippleController.value * 40);
                            final double opacity =
                                (1 - _rippleController.value - (index * 0.1))
                                    .clamp(0.0, 1.0);

                            return Container(
                              width: rippleSize,
                              height: rippleSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isCallConnected
                                    ? Colors.green.withOpacity(opacity * 0.3)
                                    : Colors.blue.withOpacity(opacity * 0.3),
                              ),
                            );
                          },
                        );
                      }),

                      // User avatar
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: colorScheme.primary.withOpacity(0.2),
                          backgroundImage: otherPersonPhotoUrl != null
                              ? NetworkImage(otherPersonPhotoUrl)
                              : null,
                          child: otherPersonPhotoUrl == null
                              ? Text(
                                  otherPersonName.isNotEmpty
                                      ? otherPersonName[0].toUpperCase()
                                      : '?',
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

                // Call status
                Text(
                  _isCallConnected ? _callDuration : _callStatus,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),

                const Spacer(flex: 2),

                // Call controls
                _buildCallControls(colorScheme),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallControls(ColorScheme colorScheme) {
    if (widget.isIncoming && !_isCallConnected && !_isCallEnding) {
      // Incoming call controls (answer/decline)
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Decline button
          _buildCallButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            onPressed: _declineCall,
            label: 'Decline',
          ),

          const SizedBox(width: 48),

          // Answer button
          _buildCallButton(
            icon: Icons.call,
            backgroundColor: Colors.green,
            onPressed: _answerCall,
            label: 'Answer',
          ),
        ],
      );
    } else {
      // Ongoing call controls
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Mute button
              _buildCallButton(
                icon: _isMuted ? Icons.mic_off : Icons.mic,
                backgroundColor: _isMuted
                    ? Colors.white.withOpacity(0.3)
                    : Colors.white.withOpacity(0.2),
                iconColor: _isMuted ? Colors.red : Colors.white,
                onPressed: _isCallConnected ? _toggleMute : null,
                label: 'Mute',
              ),

              const SizedBox(width: 24),

              // End call button
              _buildCallButton(
                icon: Icons.call_end,
                backgroundColor: Colors.red,
                size: 70,
                iconSize: 32,
                onPressed: _endCall,
                label: 'End',
              ),

              const SizedBox(width: 24),

              // Speaker button
              _buildCallButton(
                icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                backgroundColor: _isSpeakerOn
                    ? Colors.white.withOpacity(0.3)
                    : Colors.white.withOpacity(0.2),
                iconColor: _isSpeakerOn ? colorScheme.primary : Colors.white,
                onPressed: _isCallConnected ? _toggleSpeaker : null,
                label: 'Speaker',
              ),
            ],
          ),
        ],
      );
    }
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color backgroundColor,
    Color? iconColor,
    required VoidCallback? onPressed,
    required String label,
    double size = 60,
    double iconSize = 28,
  }) {
    return Column(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: FloatingActionButton(
            backgroundColor: backgroundColor,
            onPressed: onPressed,
            elevation: 8,
            child: Icon(
              icon,
              color: iconColor ?? Colors.white,
              size: iconSize,
            ),
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

  void _showExitConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Exit Call'),
          content: const Text('Are you sure you want to exit the call?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _endCall();
              },
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }
}

// Wakelock helper class to keep screen on during calls
class Wakelock {
  static bool _enabled = false;

  static Future<void> enable() async {
    if (!_enabled) {
      _enabled = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
      await SystemChannels.platform.invokeMethod(
          'SystemChrome.setEnabledSystemUIMode', <String, dynamic>{
        'mode': 'manual',
        'overlays': <String>['top', 'bottom']
      });
    }
  }

  static Future<void> disable() async {
    if (_enabled) {
      _enabled = false;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}
