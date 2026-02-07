import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class VideoCallScreen extends StatefulWidget {
  final Call call;
  final bool isIncoming;

  const VideoCallScreen({
    Key? key,
    required this.call,
    this.isIncoming = false,
  }) : super(key: key);

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  bool _isCallConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true; // Default speaker on for video calls
  bool _isCallEnding = false;
  bool _isCameraOn = true;
  bool _isBackCamera = false;
  String _callStatus = 'Connecting...';
  String _callDuration = '00:00';
  Timer? _callTimer;

  // Agora engine instance from call service
  RtcEngine? get _engine => _callService.engine;

  // Local and remote video UIDs
  int? _localUid;
  int? _remoteUid;

  // Animation controller for connecting effect
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

    // Keep screen on during call
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _callTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  // Initialize call service and listen for call status changes
  Future<void> _initialize() async {
    try {
      // Set up event handlers for video
      _setupVideoEventHandlers();

      // Listen for call status changes
      _callService
          .listenForCallStatusChanges(widget.call.callId)
          .listen(_handleCallStatusChanged, onError: _handleCallError);

      if (widget.isIncoming && widget.call.status == 'ringing') {
        setState(() {
          _callStatus = 'Incoming video call...';
        });
      } else if (!widget.isIncoming && widget.call.status == 'ringing') {
        setState(() {
          _callStatus = 'Video calling...';
        });
      } else if (widget.call.status == 'ongoing') {
        _handleCallConnected();
      }
    } catch (e) {
      print('Error initializing video call: $e');
      _showError('Failed to initialize video call');
    }
  }

  // Set up video-specific event handlers
  void _setupVideoEventHandlers() {
    if (_engine == null) return;

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        print("Local user joined the channel: ${connection.channelId}");
        setState(() {
          _localUid = connection.localUid;
        });
        _handleCallConnected();
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        print("Remote user joined: $remoteUid");
        setState(() {
          _remoteUid = remoteUid;
        });
      },
      onUserOffline: (connection, remoteUid, reason) {
        print("Remote user left: $remoteUid, reason: $reason");
        setState(() {
          _remoteUid = null;
        });
        if (reason == UserOfflineReasonType.userOfflineQuit) {
          _endCall();
        }
      },
      onError: (err, msg) {
        print("Error occurred: $err, $msg");
      },
    ));
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
    _showError('Video call connection error');

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

  // Toggle camera (on/off)
  Future<void> _toggleCamera() async {
    if (_engine == null) return;

    setState(() {
      _isCameraOn = !_isCameraOn;
    });

    await _engine!.enableLocalVideo(_isCameraOn);
  }

  // Switch camera (front/back)
  Future<void> _switchCamera() async {
    if (_engine == null || !_isCameraOn) return;

    await _engine!.switchCamera();

    setState(() {
      _isBackCamera = !_isBackCamera;
    });
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
    final size = MediaQuery.of(context).size;
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
            color: Colors.white,
            onPressed: () {
              if (_isCallConnected) {
                _endCall();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: _buildCallBody(
            size, colorScheme, otherPersonName, otherPersonPhotoUrl),
      ),
    );
  }

  Widget _buildCallBody(Size size, ColorScheme colorScheme,
      String otherPersonName, String? otherPersonPhotoUrl) {
    // If we're connected and have remote video
    if (_isCallConnected && _remoteUid != null) {
      return Stack(
        children: [
          // Remote video (full screen)
          _remoteUid != null
              ? AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: _engine!,
                    canvas: VideoCanvas(uid: _remoteUid),
                    connection: const RtcConnection(channelId: ''),
                  ),
                )
              : Container(
                  color: Colors.black,
                  child: Center(
                    child: Text(
                      'Waiting for $otherPersonName to join...',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),

          // Local video (picture-in-picture)
          Positioned(
            right: 20,
            top: 100,
            child: _isCameraOn
                ? Container(
                    width: size.width * 0.3,
                    height: size.height * 0.2,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _localUid != null
                          ? AgoraVideoView(
                              controller: VideoViewController(
                                rtcEngine: _engine!,
                                canvas: const VideoCanvas(uid: 0),
                              ),
                            )
                          : const Center(
                              child: CircularProgressIndicator(),
                            ),
                    ),
                  )
                : Container(),
          ),

          // Call info overlay at top
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                children: [
                  Text(
                    otherPersonName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _callDuration,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Call controls at bottom
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: _buildCallControls(colorScheme),
          ),
        ],
      );
    } else {
      // Connecting view or incoming call view (similar to audio call)
      return Container(
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
      );
    }
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
            icon: Icons.videocam,
            backgroundColor: Colors.green,
            onPressed: _answerCall,
            label: 'Answer',
          ),
        ],
      );
    } else if (_isCallConnected) {
      // Video call controls with camera toggles
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Mute button
                _buildCallButton(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  backgroundColor: Colors.black.withOpacity(0.5),
                  iconColor: _isMuted ? Colors.red : Colors.white,
                  onPressed: _toggleMute,
                  label: 'Mute',
                ),
    
                // Camera toggle button
                _buildCallButton(
                  icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                  backgroundColor: Colors.black.withOpacity(0.5),
                  iconColor: _isCameraOn ? Colors.white : Colors.red,
                  onPressed: _toggleCamera,
                  label: _isCameraOn ? 'Camera' : 'Camera Off',
                ),
    
                // End call button
                _buildCallButton(
                  icon: Icons.call_end,
                  backgroundColor: Colors.red,
                  size: 70,
                  iconSize: 32,
                  onPressed: _endCall,
                  label: 'End',
                ),
    
                // Switch camera button
                _buildCallButton(
                  icon: Icons.flip_camera_ios,
                  backgroundColor: Colors.black.withOpacity(0.5),
                  iconColor: Colors.white,
                  onPressed: _isCameraOn ? _switchCamera : null,
                  label: 'Flip',
                ),
    
                // Speaker button
                _buildCallButton(
                  icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                  backgroundColor: Colors.black.withOpacity(0.5),
                  iconColor: _isSpeakerOn ? Colors.white : Colors.red,
                  onPressed: _toggleSpeaker,
                  label: 'Speaker',
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      // Connecting controls (just end call)
      return _buildCallButton(
        icon: Icons.call_end,
        backgroundColor: Colors.red,
        size: 70,
        iconSize: 32,
        onPressed: _endCall,
        label: 'Cancel',
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

  // Show exit confirmation dialog
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
                _endCall();
                Navigator.of(context).pop();
              },
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }
}
