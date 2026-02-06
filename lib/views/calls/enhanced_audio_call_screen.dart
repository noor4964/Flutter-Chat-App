import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/calls/enhanced_call_service.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/widgets/web_layout_wrapper.dart';

class EnhancedAudioCallScreen extends StatefulWidget {
  final Call call;
  final bool isIncoming;

  const EnhancedAudioCallScreen({
    Key? key,
    required this.call,
    this.isIncoming = false,
  }) : super(key: key);

  @override
  _EnhancedAudioCallScreenState createState() => _EnhancedAudioCallScreenState();
}

class _EnhancedAudioCallScreenState extends State<EnhancedAudioCallScreen>
    with TickerProviderStateMixin {
  final EnhancedCallService _enhancedCallService = EnhancedCallService();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // Call state
  bool _isCallConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCallEnding = false;
  bool _isRecording = false;
  bool _showDiagnostics = false;
  bool _isFixingAudio = false;
  String _callStatus = 'Connecting...';
  String _callDuration = '00:00';
  Timer? _callTimer;

  // Enhanced features
  CallQuality _callQuality = CallQuality.excellent;
  double _volumeLevel = 1.0;
  bool _echoCancellation = true;
  bool _noiseSuppression = true;
  bool _showAdvancedControls = false;

  // Animation controllers
  late AnimationController _rippleController;
  late AnimationController _qualityIndicatorController;
  late AnimationController _pulseController;
  late AnimationController _recordingController;

  // Animations
  late Animation<double> _qualityAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<Color?> _recordingAnimation;

  // Stream subscriptions
  StreamSubscription<CallState>? _callStateSubscription;
  StreamSubscription<CallQuality>? _callQualitySubscription;
  StreamSubscription<CallStatistics>? _callStatisticsSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initialize();
    _setupSystemUI();
  }

  @override
  void dispose() {
    _disposeAnimations();
    _disposeSubscriptions();
    _callTimer?.cancel();
    Wakelock.disable();
    super.dispose();
  }

  void _initializeAnimations() {
    // Ripple animation for avatar
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Quality indicator animation
    _qualityIndicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _qualityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _qualityIndicatorController, curve: Curves.easeInOut),
    );

    // Pulse animation for active call
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Recording indicator animation
    _recordingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _recordingAnimation = ColorTween(
      begin: Colors.red,
      end: Colors.red.withOpacity(0.3),
    ).animate(_recordingController);

    _rippleController.repeat();
  }

  void _disposeAnimations() {
    _rippleController.dispose();
    _qualityIndicatorController.dispose();
    _pulseController.dispose();
    _recordingController.dispose();
  }

  void _disposeSubscriptions() {
    _callStateSubscription?.cancel();
    _callQualitySubscription?.cancel();
    _callStatisticsSubscription?.cancel();
  }

  void _setupSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    Wakelock.enable();
  }

  Future<void> _initialize() async {
    try {
      // Initialize enhanced call service
      await _enhancedCallService.initialize();

      // Subscribe to enhanced streams
      _callStateSubscription = _enhancedCallService.callStateStream.listen(_handleCallStateChanged);
      _callQualitySubscription = _enhancedCallService.callQualityStream.listen(_handleCallQualityChanged);
      _callStatisticsSubscription = _enhancedCallService.callStatisticsStream.listen(_handleCallStatisticsChanged);

      // Listen for base call status changes
      _enhancedCallService
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
      print('Error initializing enhanced call: $e');
      _showError('Failed to initialize call');
    }
  }

  void _handleCallStateChanged(CallState state) {
    if (!mounted) return;

    switch (state) {
      case CallState.connected:
        _handleCallConnected();
        break;
      case CallState.ending:
      case CallState.ended:
        _handleCallEnded(false);
        break;
      case CallState.error:
        _handleCallError('Connection error');
        break;
      default:
        break;
    }
  }

  void _handleCallQualityChanged(CallQuality quality) {
    if (!mounted) return;

    setState(() {
      _callQuality = quality;
    });

    // Animate quality indicator
    _qualityIndicatorController.forward().then((_) {
      _qualityIndicatorController.reverse();
    });

    // Provide haptic feedback for quality changes
    if (quality == CallQuality.poor || quality == CallQuality.critical) {
      HapticFeedback.heavyImpact();
    }
  }

  void _handleCallStatisticsChanged(CallStatistics statistics) {
    // Update UI with statistics if needed
    // This could show network latency, packet loss, etc.
  }

  void _handleCallStatusChanged(Call call) {
    if (call.status == 'ongoing' && !_isCallConnected) {
      _handleCallConnected();
    } else if (call.status == 'ended' || call.status == 'declined') {
      _handleCallEnded(call.status == 'declined');
    }
  }

  void _handleCallConnected() {
    if (!mounted) return;

    setState(() {
      _isCallConnected = true;
      _callStatus = 'Connected';
    });

    // Start pulse animation for connected state
    _pulseController.repeat(reverse: true);

    // Vibrate to indicate call connected
    HapticFeedback.mediumImpact();

    // Start the call timer
    _startCallTimer();
  }

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

  void _handleCallEnded(bool isDeclined) {
    if (!mounted || _isCallEnding) return;

    _isCallEnding = true;
    _callTimer?.cancel();
    _pulseController.stop();

    HapticFeedback.mediumImpact();

    setState(() {
      _callStatus = isDeclined ? 'Call declined' : 'Call ended';
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _handleCallError(dynamic error) {
    print('Enhanced call error: $error');
    _showError('Call connection error');

    _enhancedCallService.endCall();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

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

  // Enhanced control methods
  Future<void> _toggleMute() async {
    bool isMuted = await _enhancedCallService.toggleMute();
    HapticFeedback.selectionClick();

    if (mounted) {
      setState(() {
        _isMuted = isMuted;
      });
    }
  }

  Future<void> _toggleSpeaker() async {
    bool isSpeakerOn = await _enhancedCallService.toggleSpeaker();
    HapticFeedback.selectionClick();

    if (mounted) {
      setState(() {
        _isSpeakerOn = isSpeakerOn;
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final recordingPath = await _enhancedCallService.stopRecording();
      _recordingController.stop();
      HapticFeedback.mediumImpact();

      if (recordingPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording saved: $recordingPath'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      final success = await _enhancedCallService.startRecording();
      if (success) {
        _recordingController.repeat(reverse: true);
        HapticFeedback.mediumImpact();
      }
    }

    if (mounted) {
      setState(() {
        _isRecording = _enhancedCallService.isRecording;
      });
    }
  }

  Future<void> _setVolume(double value) async {
    await _enhancedCallService.setVolumeLevel(value);
    setState(() {
      _volumeLevel = value;
    });
  }

  Future<void> _toggleEchoCancellation() async {
    await _enhancedCallService.setEchoCancellation(!_echoCancellation);
    setState(() {
      _echoCancellation = !_echoCancellation;
    });
  }

  Future<void> _toggleNoiseSuppression() async {
    await _enhancedCallService.setNoiseSuppression(!_noiseSuppression);
    setState(() {
      _noiseSuppression = !_noiseSuppression;
    });
  }

  Future<void> _endCall() async {
    if (_isCallEnding) return;

    setState(() {
      _isCallEnding = true;
      _callStatus = 'Ending call...';
    });

    await _enhancedCallService.endCall();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _answerCall() async {
    try {
      setState(() {
        _callStatus = 'Connecting...';
      });

      bool success = await _enhancedCallService.answerCall(widget.call.callId);

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

  Future<void> _declineCall() async {
    try {
      setState(() {
        _isCallEnding = true;
        _callStatus = 'Declining call...';
      });

      await _enhancedCallService.endCall(isDeclined: true);

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

  // Attempt to fix audio issues
  Future<void> _attemptToFixAudio() async {
    if (_isFixingAudio) return;
    
    setState(() {
      _isFixingAudio = true;
    });
    
    try {
      await _enhancedCallService.fixVoiceIssues();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio fix attempted'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFixingAudio = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isCurrentUserCaller = _currentUser?.uid == widget.call.callerId;

    final String otherPersonName =
        isCurrentUserCaller ? widget.call.receiverName : widget.call.callerName;

    final String? otherPersonPhotoUrl = isCurrentUserCaller
        ? widget.call.receiverPhotoUrl
        : widget.call.callerPhotoUrl;

    Widget callInterface = PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        // For incoming calls, allow direct exit without confirmation
        if (widget.isIncoming && !_isCallConnected) {
          _declineCall();
        } else {
          _showExitConfirmationDialog();
        }
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
              } else if (widget.isIncoming) {
                _declineCall();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            // Call quality indicator
            _buildCallQualityIndicator(),
            // Advanced controls toggle
            IconButton(
              icon: Icon(_showAdvancedControls ? Icons.expand_less : Icons.expand_more),
              onPressed: () {
                setState(() {
                  _showAdvancedControls = !_showAdvancedControls;
                });
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            Container(
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
    
                    // Enhanced user avatar with quality-based ripples
                    _buildEnhancedAvatar(otherPersonName, otherPersonPhotoUrl),
    
                    const SizedBox(height: 24),
    
                    // Name with enhanced typography
                    _buildUserName(otherPersonName),
    
                    const SizedBox(height: 12),
    
                    // Enhanced call status with recording indicator
                    _buildCallStatus(),
    
                    const SizedBox(height: 24),
    
                    // Advanced controls panel (collapsible)
                    if (_showAdvancedControls) _buildAdvancedControls(),
    
                    const Spacer(flex: 2),
    
                    // Enhanced call controls
                    _buildEnhancedCallControls(colorScheme),
    
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            
            // Call Diagnostics Widget
            if (_isCallConnected)
              _buildCallDiagnosticsWidget(),
          ],
        ),
      ),
    );

    // For web platforms with sufficient width, use the three-column layout
    if (PlatformHelper.isWeb && MediaQuery.of(context).size.width >= 1200) {
      return WebLayoutWrapper(
        title: 'Voice Call - $otherPersonName',
        leftSidebar: _buildCallInfoSidebar(otherPersonName, otherPersonPhotoUrl),
        rightSidebar: _buildCallControlsSidebar(),
        showLeftSidebar: true,
        showRightSidebar: true,
        leftSidebarWidth: 300,
        rightSidebarWidth: 300,
        child: callInterface,
      );
    }

    // For mobile or small screens, use the traditional layout
    return callInterface;
  }

  Widget _buildCallQualityIndicator() {
    Color qualityColor;
    IconData qualityIcon;

    switch (_callQuality) {
      case CallQuality.excellent:
        qualityColor = Colors.green;
        qualityIcon = Icons.signal_cellular_4_bar;
        break;
      case CallQuality.good:
        qualityColor = Colors.lightGreen;
        qualityIcon = Icons.signal_cellular_4_bar;
        break;
      case CallQuality.fair:
        qualityColor = Colors.yellow;
        qualityIcon = Icons.signal_cellular_alt;
        break;
      case CallQuality.poor:
        qualityColor = Colors.orange;
        qualityIcon = Icons.signal_cellular_connected_no_internet_4_bar;
        break;
      case CallQuality.critical:
        qualityColor = Colors.red;
        qualityIcon = Icons.signal_cellular_nodata;
        break;
    }

    return AnimatedBuilder(
      animation: _qualityAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(right: 8),
          child: Icon(
            qualityIcon,
            color: qualityColor.withOpacity(0.7 + _qualityAnimation.value * 0.3),
            size: 20 + _qualityAnimation.value * 4,
          ),
        );
      },
    );
  }

  Widget _buildEnhancedAvatar(String name, String? photoUrl) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isCallConnected ? _pulseAnimation.value : 1.0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Enhanced ripple effects based on call quality
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

                      Color rippleColor = _isCallConnected
                          ? _getQualityColor().withOpacity(opacity * 0.3)
                          : Colors.blue.withOpacity(opacity * 0.3);

                      return Container(
                        width: rippleSize,
                        height: rippleSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: rippleColor,
                        ),
                      );
                    },
                  );
                }),

                // Enhanced user avatar with recording indicator
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.2),
                    border: _isRecording
                        ? Border.all(
                            color: Colors.red,
                            width: 3,
                          )
                        : null,
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
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
        },
      ),
    );
  }

  Widget _buildUserName(String name) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: TextStyle(
        fontSize: _isCallConnected ? 32 : 28,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      child: Text(name),
    );
  }

  Widget _buildCallStatus() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Recording indicator
        if (_isRecording)
          AnimatedBuilder(
            animation: _recordingAnimation,
            builder: (context, child) {
              return Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recordingAnimation.value,
                ),
              );
            },
          ),
        Text(
          _isCallConnected ? _callDuration : _callStatus,
          style: TextStyle(
            fontSize: 18,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Advanced Controls',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Volume control
          Row(
            children: [
              const Icon(Icons.volume_up, color: Colors.white70, size: 20),
              Expanded(
                child: Slider(
                  value: _volumeLevel,
                  onChanged: _setVolume,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white30,
                ),
              ),
            ],
          ),
          
          // Echo cancellation toggle
          _buildAdvancedToggle(
            'Echo Cancellation',
            _echoCancellation,
            Icons.hearing,
            _toggleEchoCancellation,
          ),
          
          // Noise suppression toggle
          _buildAdvancedToggle(
            'Noise Suppression',
            _noiseSuppression,
            Icons.noise_control_off,
            _toggleNoiseSuppression,
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedToggle(
    String title,
    bool value,
    IconData icon,
    VoidCallback onToggle,
  ) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Switch(
          value: value,
          onChanged: (_) => onToggle(),
          activeColor: Colors.white,
          activeTrackColor: Colors.white30,
        ),
      ],
    );
  }

  Widget _buildCallDiagnosticsWidget() {
    if (!_showDiagnostics) {
      // Show a small icon that can be tapped to expand
      return Positioned(
        top: 40,
        right: 10,
        child: GestureDetector(
          onTap: () => setState(() => _showDiagnostics = true),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.info_outline,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );
    }
    
    return Positioned(
      top: 40,
      right: 10,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Call Diagnostics',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showDiagnostics = false),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            Text(
              'Platform: ${PlatformHelper.isWeb ? 'Web' : PlatformHelper.isAndroid ? 'Android' : PlatformHelper.isIOS ? 'iOS' : 'Desktop'}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            
            const SizedBox(height: 4),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Audio status:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                _buildStatusIndicator(),
              ],
            ),
            
            const SizedBox(height: 8),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isFixingAudio ? null : _attemptToFixAudio,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: _isFixingAudio 
                    ? const SizedBox(
                        width: 16, 
                        height: 16, 
                        child: CircularProgressIndicator(
                          strokeWidth: 2, 
                          color: Colors.white,
                        )
                      )
                    : const Text('Fix Audio'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusIndicator() {
    final bool isAudioWorking = _enhancedCallService.isAudioWorking();
    
    return Row(
      children: [
        Icon(
          isAudioWorking ? Icons.check_circle : Icons.warning,
          color: isAudioWorking ? Colors.green : Colors.orange,
          size: 14,
        ),
        const SizedBox(width: 4),
        Text(
          isAudioWorking ? 'OK' : 'Issues',
          style: TextStyle(
            color: isAudioWorking ? Colors.green : Colors.orange,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedCallControls(ColorScheme colorScheme) {
    if (widget.isIncoming && !_isCallConnected && !_isCallEnding) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildCallButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            onPressed: _declineCall,
            label: 'Decline',
          ),
          const SizedBox(width: 48),
          _buildCallButton(
            icon: Icons.call,
            backgroundColor: Colors.green,
            onPressed: _answerCall,
            label: 'Answer',
          ),
        ],
      );
    } else {
      return Column(
        children: [
          // Main controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              _buildCallButton(
                icon: Icons.call_end,
                backgroundColor: Colors.red,
                size: 70,
                iconSize: 32,
                onPressed: _endCall,
                label: 'End',
              ),
              const SizedBox(width: 24),
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
          
          const SizedBox(height: 16),
          
          // Secondary controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildCallButton(
                icon: _isRecording ? Icons.stop : Icons.fiber_manual_record,
                backgroundColor: _isRecording
                    ? Colors.red.withOpacity(0.8)
                    : Colors.white.withOpacity(0.2),
                iconColor: _isRecording ? Colors.white : Colors.red,
                onPressed: _isCallConnected ? _toggleRecording : null,
                label: _isRecording ? 'Stop Rec' : 'Record',
                size: 50,
                iconSize: 20,
              ),
              
              const SizedBox(width: 24),
              
              // Add "Fix Audio" button
              _buildCallButton(
                icon: Icons.settings_voice,
                backgroundColor: Colors.blue.withOpacity(0.7),
                onPressed: _isFixingAudio ? null : _attemptToFixAudio,
                label: 'Fix Audio',
                size: 50,
                iconSize: 20,
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
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Color _getQualityColor() {
    switch (_callQuality) {
      case CallQuality.excellent:
        return Colors.green;
      case CallQuality.good:
        return Colors.lightGreen;
      case CallQuality.fair:
        return Colors.yellow;
      case CallQuality.poor:
        return Colors.orange;
      case CallQuality.critical:
        return Colors.red;
    }
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

  Widget _buildCallInfoSidebar(String otherPersonName, String? otherPersonPhotoUrl) {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          
          // Large avatar
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundImage: otherPersonPhotoUrl != null
                  ? NetworkImage(otherPersonPhotoUrl)
                  : null,
              child: otherPersonPhotoUrl == null
                  ? Icon(Icons.person, size: 60)
                  : null,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Name
          Text(
            otherPersonName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 8),
          
          // Call status
          Text(
            _callStatus,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).primaryColor,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 8),
          
          // Call duration
          if (_isCallConnected)
            Text(
              _callDuration,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          
          const SizedBox(height: 30),
          
          // Call quality info
          _buildCallQualityInfo(),
          
          const Spacer(),
          
          // Recording status
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Recording',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCallControlsSidebar() {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Call Controls',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Basic controls
          _buildSidebarControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: _isMuted ? 'Unmute' : 'Mute',
            isActive: _isMuted,
            onTap: _toggleMute,
          ),
          
          const SizedBox(height: 12),
          
          _buildSidebarControlButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            label: _isSpeakerOn ? 'Speaker On' : 'Speaker Off',
            isActive: _isSpeakerOn,
            onTap: _toggleSpeaker,
          ),
          
          const SizedBox(height: 12),
          
          _buildSidebarControlButton(
            icon: _isRecording ? Icons.stop : Icons.fiber_manual_record,
            label: _isRecording ? 'Stop Recording' : 'Start Recording',
            isActive: _isRecording,
            onTap: _toggleRecording,
          ),
          
          const SizedBox(height: 20),
          
          Divider(color: Theme.of(context).dividerColor),
          
          const SizedBox(height: 20),
          
          // Advanced controls section
          Text(
            'Audio Settings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Volume control
          Text('Volume', style: Theme.of(context).textTheme.bodyMedium),
          Slider(
            value: _volumeLevel,
            onChanged: _setVolume,
            min: 0.0,
            max: 1.0,
          ),
          
          const SizedBox(height: 16),
          
          // Echo cancellation
          SwitchListTile(
            title: Text('Echo Cancellation'),
            subtitle: Text('Reduce echo effects'),
            value: _echoCancellation,
            onChanged: (value) => _toggleEchoCancellation(),
            contentPadding: EdgeInsets.zero,
          ),
          
          // Noise suppression
          SwitchListTile(
            title: Text('Noise Suppression'),
            subtitle: Text('Filter background noise'),
            value: _noiseSuppression,
            onChanged: (value) => _toggleNoiseSuppression(),
            contentPadding: EdgeInsets.zero,
          ),
          
          const Spacer(),
          
          // End call button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _endCall,
              icon: Icon(Icons.call_end, color: Colors.white),
              label: Text('End Call', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallQualityInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Call Quality:', style: Theme.of(context).textTheme.bodySmall),
              _buildCallQualityIndicator(),
            ],
          ),
          if (_enhancedCallService.lastStatistics != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Duration:', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  _callDuration,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSidebarControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? Theme.of(context).primaryColor.withOpacity(0.3)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).iconTheme.color,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isActive
                    ? Theme.of(context).primaryColor
                    : null,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Enhanced Wakelock helper class
class Wakelock {
  static bool _enabled = false;

  static Future<void> enable() async {
    if (!_enabled) {
      _enabled = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    }
  }

  static Future<void> disable() async {
    if (_enabled) {
      _enabled = false;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}