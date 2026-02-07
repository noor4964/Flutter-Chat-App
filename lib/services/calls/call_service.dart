import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

// Agora App ID from console
const String agoraAppId =
    'edbb53879a314cc8bd7417e867d4a322';

class Call {
  final String callId;
  final String callerId;
  final String receiverId;
  final String callerName;
  final String? callerPhotoUrl;
  final String receiverName;
  final String? receiverPhotoUrl;
  final DateTime timestamp;
  final bool isVideo;
  final String status; // 'ringing', 'ongoing', 'ended', 'declined', 'missed'
  final int? duration; // in seconds, null if call is not ended
  final String? missedBy; // userId of the person who missed the call

  Call({
    required this.callId,
    required this.callerId,
    required this.receiverId,
    required this.callerName,
    this.callerPhotoUrl,
    required this.receiverName,
    this.receiverPhotoUrl,
    required this.timestamp,
    this.isVideo = false,
    required this.status,
    this.duration,
    this.missedBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'receiverId': receiverId,
      'callerName': callerName,
      'callerPhotoUrl': callerPhotoUrl,
      'receiverName': receiverName,
      'receiverPhotoUrl': receiverPhotoUrl,
      'timestamp': FieldValue.serverTimestamp(),
      'isVideo': isVideo,
      'status': status,
      'duration': duration,
      'missedBy': missedBy,
    };
  }

  factory Call.fromMap(Map<String, dynamic> map) {
    DateTime timestamp;
    if (map['timestamp'] is Timestamp) {
      timestamp = (map['timestamp'] as Timestamp).toDate();
    } else if (map['timestamp'] is DateTime) {
      timestamp = map['timestamp'] as DateTime;
    } else {
      timestamp = DateTime.now();
    }

    return Call(
      callId: map['callId'] ?? '',
      callerId: map['callerId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerPhotoUrl: map['callerPhotoUrl'],
      receiverName: map['receiverName'] ?? '',
      receiverPhotoUrl: map['receiverPhotoUrl'],
      timestamp: timestamp,
      isVideo: map['isVideo'] ?? false,
      status: map['status'] ?? 'unknown',
      duration: map['duration'],
      missedBy: map['missedBy'],
    );
  }
}

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Agora SDK client
  RtcEngine? _engine;
  RtcEngine? get engine => _engine;

  // Stream controller for call status updates
  final _callStatusController = StreamController<Call>.broadcast();
  Stream<Call> get callStatus => _callStatusController.stream;

  // Track the current call
  Call? _currentCall;
  Call? get currentCall => _currentCall;

  // Mute state
  bool _isMuted = false;

  // Caller/Receiver distinction - fixes the onJoinChannelSuccess bug
  bool _isReceiver = false;

  // Call timeout - auto-end unanswered calls after 30 seconds
  Timer? _callTimeoutTimer;
  static const int callTimeoutSeconds = 30;

  // Singleton
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  bool _isUserAuthenticated() {
    return _auth.currentUser != null;
  }

  // Initialize the Agora SDK
  Future<void> initialize() async {
    if (_engine != null) return;

    if (!_isUserAuthenticated()) {
      throw Exception("User must be authenticated to initialize call service");
    }

    try {
      // On web, skip permissions during init — browser requires a user gesture
      // (click/tap) to grant mic access. Permissions are requested later in
      // startCall()/answerCall() which run in user gesture context.
      if (!PlatformHelper.isWeb) {
        bool permissionsGranted = await _requestPermissions(false);
        if (!permissionsGranted) {
          throw Exception("Required permissions were denied");
        }
      }

      try {
        print("Creating Agora RTC Engine on platform: ${PlatformHelper.isWeb ? 'WEB' : PlatformHelper.isAndroid ? 'ANDROID' : 'iOS/DESKTOP'}");
        _engine = createAgoraRtcEngine();

        if (PlatformHelper.isWeb) {
          await _engine!.initialize(const RtcEngineContext(
            appId: agoraAppId,
            channelProfile: ChannelProfileType.channelProfileCommunication,
            audioScenario: AudioScenarioType.audioScenarioDefault,
          ));
          // Only enable the audio subsystem — do NOT call enableLocalAudio(true)
          // here. That triggers getUserMedia which browsers block without a user
          // gesture. It will be called from startCall/answerCall instead.
          await _engine!.enableAudio();
          await Future.delayed(const Duration(milliseconds: 300));
        } else {
          await _engine!.initialize(const RtcEngineContext(
            appId: agoraAppId,
            channelProfile: ChannelProfileType.channelProfileCommunication,
            audioScenario: AudioScenarioType.audioScenarioDefault,
          ));
          // Enable audio immediately after init — critical for mobile
          await _engine!.enableAudio();
          await _engine!.enableLocalAudio(true);
        }

        // Register event handler
        _engine!.registerEventHandler(
          RtcEngineEventHandler(
            onJoinChannelSuccess: (connection, elapsed) {
              print("Local user joined channel: ${connection.channelId}");
              // Only the RECEIVER should update status to 'ongoing' on join.
              // The CALLER stays in 'ringing' until Firestore listener
              // detects the receiver changed the status.
              if (_isReceiver) {
                _updateCallStatus('ongoing');
              }
            },
            onUserJoined: (connection, remoteUid, elapsed) {
              print("Remote user joined: $remoteUid");
              // Cancel call timeout since the other party joined
              _callTimeoutTimer?.cancel();
              // Subscribe to remote audio
              _engine?.muteRemoteAudioStream(uid: remoteUid, mute: false);
            },
            onUserOffline: (connection, remoteUid, reason) {
              print("Remote user left: $remoteUid, reason: $reason");
              if (reason == UserOfflineReasonType.userOfflineQuit) {
                endCall();
              }
            },
            onLocalAudioStateChanged: (connection, state, error) {
              print("Local audio state: $state, error: $error");
              if (state == LocalAudioStreamState.localAudioStreamStateFailed) {
                // Simple recovery by toggling audio
                _engine?.enableLocalAudio(false);
                Future.delayed(const Duration(milliseconds: 500), () {
                  _engine?.enableLocalAudio(true);
                });
              }
            },
            onError: (err, msg) {
              print("Agora Error: $err, $msg");
            },
          ),
        );

        print("Agora RTC Engine initialized successfully");
      } catch (e) {
        print("Error initializing Agora RTC Engine: $e");

        if (PlatformHelper.isDesktop) {
          try {
            _engine = createAgoraRtcEngine();
            await Future.delayed(const Duration(milliseconds: 500));
            await _engine!.initialize(const RtcEngineContext(
              appId: agoraAppId,
              channelProfile: ChannelProfileType.channelProfileCommunication,
            ));
            print("Alternative Agora initialization successful");
          } catch (desktopError) {
            print("Error in alternative initialization: $desktopError");
            _engine = null;
            rethrow;
          }
        } else {
          _engine = null;
          rethrow;
        }
      }
    } catch (e) {
      print("Error initializing Agora: $e");
      _engine = null;
      rethrow;
    }
  }

  // Start a call to another user
  Future<Call?> startCall(String receiverId, bool isVideoCall) async {
    try {
      _isReceiver = false; // This is the caller

      // Handle desktop platforms
      if (PlatformHelper.isDesktop) {
        print('Call functionality not fully supported on desktop');
        User? user = _auth.currentUser;
        if (user == null) throw Exception("User is not logged in");

        String receiverName = 'Unknown';
        try {
          DocumentSnapshot receiverDoc =
              await _firestore.collection('users').doc(receiverId).get();
          if (receiverDoc.exists) {
            final receiverData = receiverDoc.data() as Map<String, dynamic>;
            receiverName = receiverData['username'] ?? 'Unknown';
          }
        } catch (e) {
          print('Unable to fetch receiver details: $e');
        }

        Call call = Call(
          callId: 'desktop-mock-${DateTime.now().millisecondsSinceEpoch}',
          callerId: user.uid,
          receiverId: receiverId,
          callerName: user.displayName ?? 'You',
          receiverName: receiverName,
          timestamp: DateTime.now(),
          isVideo: isVideoCall,
          status: 'desktop-mock',
        );
        _currentCall = call;
        _callStatusController.add(call);
        return call;
      }

      // Web platform pre-checks
      if (PlatformHelper.isWeb) {
        if (_currentCall != null) {
          try {
            await _engine?.leaveChannel();
          } catch (e) {
            print("Web cleanup of previous call: $e");
          }
          _currentCall = null;
        }
      }

      // Ensure engine is initialized
      if (_engine == null) {
        await initialize();
        if (_engine == null) throw Exception("Failed to initialize call engine");
        if (PlatformHelper.isWeb) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // Check permissions
      bool permissionsGranted = await _requestPermissions(isVideoCall);
      if (!permissionsGranted) {
        throw Exception("Required call permissions were denied");
      }

      // Get current user
      User? user = _auth.currentUser;
      if (user == null) throw Exception("User is not logged in");

      // Get receiver details
      DocumentSnapshot receiverDoc =
          await _firestore.collection('users').doc(receiverId).get();
      if (!receiverDoc.exists) throw Exception("Receiver not found");
      Map<String, dynamic> receiverData =
          receiverDoc.data() as Map<String, dynamic>;

      // Get caller details
      DocumentSnapshot callerDoc =
          await _firestore.collection('users').doc(user.uid).get();
      Map<String, dynamic> callerData =
          callerDoc.data() as Map<String, dynamic>;

      // Create call
      String callId = _firestore.collection('calls').doc().id;
      Call call = Call(
        callId: callId,
        callerId: user.uid,
        receiverId: receiverId,
        callerName: callerData['username'] ?? 'Unknown',
        callerPhotoUrl: callerData['profileImageUrl'],
        receiverName: receiverData['username'] ?? 'Unknown',
        receiverPhotoUrl: receiverData['profileImageUrl'],
        timestamp: DateTime.now(),
        isVideo: isVideoCall,
        status: 'ringing',
      );

      // Save to Firestore
      await _firestore.collection('calls').doc(callId).set(call.toMap());

      _currentCall = call;
      _callStatusController.add(call);

      // Show CallKit UI
      await _showCallkitIncoming(call, isOutgoing: true);

      // Configure audio
      await _configureAudioSession(isVideoCall);

      // Start call timeout timer (30 seconds)
      _callTimeoutTimer?.cancel();
      _callTimeoutTimer = Timer(Duration(seconds: callTimeoutSeconds), () {
        _handleCallTimeout();
      });

      // Join Agora channel
      await _joinChannel(callId, isVideoCall);

      return call;
    } catch (e) {
      print("Error starting call: $e");
      _callTimeoutTimer?.cancel();
      return null;
    }
  }

  // Handle call timeout (unanswered after 30 seconds)
  Future<void> _handleCallTimeout() async {
    if (_currentCall == null) return;
    if (_currentCall!.status != 'ringing') return;

    print("Call timeout - marking as missed");
    try {
      await _firestore.collection('calls').doc(_currentCall!.callId).update({
        'status': 'missed',
        'missedBy': _currentCall!.receiverId,
      });

      await _engine?.leaveChannel();
      await FlutterCallkitIncoming.endAllCalls();

      // Notify listeners
      try {
        DocumentSnapshot callDoc =
            await _firestore.collection('calls').doc(_currentCall!.callId).get();
        if (callDoc.exists) {
          Call missedCall = Call.fromMap(callDoc.data() as Map<String, dynamic>);
          _callStatusController.add(missedCall);
        }
      } catch (e) {
        print("Error fetching missed call data: $e");
      }

      _currentCall = null;
    } catch (e) {
      print("Error handling call timeout: $e");
    }
  }

  // Answer an incoming call
  Future<bool> answerCall(String callId) async {
    try {
      _isReceiver = true; // This is the receiver
      _callTimeoutTimer?.cancel(); // Cancel any timeout

      DocumentSnapshot callDoc =
          await _firestore.collection('calls').doc(callId).get();
      if (!callDoc.exists) throw Exception("Call not found");

      Call call = Call.fromMap(callDoc.data() as Map<String, dynamic>);

      if (_engine == null) await initialize();

      bool permissionsGranted = await _requestPermissions(call.isVideo);
      if (!permissionsGranted) {
        throw Exception("Required permissions were denied for answering call");
      }

      _currentCall = call;
      _callStatusController.add(call);

      // Update status to 'ongoing'
      await _firestore.collection('calls').doc(callId).update({
        'status': 'ongoing',
      });

      // Configure audio
      await _configureAudioSession(call.isVideo);

      // Join channel
      await _joinChannel(callId, call.isVideo);

      return true;
    } catch (e) {
      print("Error answering call: $e");
      return false;
    }
  }

  // End or decline a call
  Future<void> endCall({bool isDeclined = false}) async {
    if (_currentCall == null) return;

    _callTimeoutTimer?.cancel();

    try {
      await _engine?.leaveChannel();

      int? duration;
      if (_currentCall!.status == 'ongoing') {
        duration = DateTime.now().difference(_currentCall!.timestamp).inSeconds;
      }

      await _firestore.collection('calls').doc(_currentCall!.callId).update({
        'status': isDeclined ? 'declined' : 'ended',
        'duration': duration,
      });

      await FlutterCallkitIncoming.endAllCalls();

      DocumentSnapshot callDoc =
          await _firestore.collection('calls').doc(_currentCall!.callId).get();
      if (callDoc.exists) {
        Call updatedCall = Call.fromMap(callDoc.data() as Map<String, dynamic>);
        _callStatusController.add(updatedCall);
      }

      _currentCall = null;
      _isMuted = false;
    } catch (e) {
      print("Error ending call: $e");
    }
  }

  // Toggle mute
  Future<bool> toggleMute() async {
    if (_engine == null) return false;

    try {
      _isMuted = !_isMuted;
      await _engine!.muteLocalAudioStream(_isMuted);
      await _engine!.adjustRecordingSignalVolume(_isMuted ? 0 : 100);
      return _isMuted;
    } catch (e) {
      print("Error toggling mute: $e");
      return _isMuted;
    }
  }

  // Toggle speaker
  Future<bool> toggleSpeaker() async {
    if (_engine == null) return false;

    try {
      bool isSpeakerphoneEnabled = await _engine!.isSpeakerphoneEnabled();
      await _engine!.setEnableSpeakerphone(!isSpeakerphoneEnabled);
      return !isSpeakerphoneEnabled;
    } catch (e) {
      print("Error toggling speaker: $e");
      return false;
    }
  }

  // Listen for incoming calls
  Stream<Call> listenForIncomingCalls() {
    User? user = _auth.currentUser;
    if (user == null) throw Exception("User is not logged in");

    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        Call call = Call.fromMap(snapshot.docs.first.data());
        _currentCall = call;
        _showCallkitIncoming(call, isOutgoing: false);
        return call;
      }
      return Call(
        callId: 'no-call',
        callerId: '',
        receiverId: user.uid,
        callerName: '',
        receiverName: '',
        timestamp: DateTime.now(),
        status: 'none',
      );
    }).handleError((error) {
      print("Error in incoming calls stream: $error");
      return Call(
        callId: 'error',
        callerId: '',
        receiverId: user.uid,
        callerName: 'Error',
        receiverName: '',
        timestamp: DateTime.now(),
        status: 'error',
      );
    });
  }

  // Listen for call status changes
  Stream<Call> listenForCallStatusChanges(String callId) {
    return _firestore
        .collection('calls')
        .doc(callId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        Call call = Call.fromMap(snapshot.data() as Map<String, dynamic>);
        _currentCall = call;

        if (call.status == 'declined' ||
            call.status == 'ended' ||
            call.status == 'missed') {
          _callTimeoutTimer?.cancel();
          FlutterCallkitIncoming.endAllCalls();
          _engine?.leaveChannel();
          _currentCall = null;
        }

        return call;
      }
      return Call(
        callId: callId,
        callerId: '',
        receiverId: '',
        callerName: '',
        receiverName: '',
        timestamp: DateTime.now(),
        status: 'not_found',
      );
    }).handleError((error) {
      print("Error in call status stream: $error");
      return Call(
        callId: callId,
        callerId: '',
        receiverId: '',
        callerName: 'Error',
        receiverName: '',
        timestamp: DateTime.now(),
        status: 'error',
      );
    });
  }

  // ─── Private Methods ──────────────────────────────────

  // Join an Agora channel with platform-specific handling
  Future<void> _joinChannel(String callId, bool isVideoCall) async {
    try {
      ChannelMediaOptions channelOptions;

      if (PlatformHelper.isWeb) {
        // Audio already configured by _configureAudioSession — just set channel options
        channelOptions = const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: false,
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
        );
      } else {
        channelOptions = ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: isVideoCall,
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideoCall,
        );
      }

      await _engine!.joinChannel(
        token: '',
        channelId: callId,
        uid: 0,
        options: channelOptions,
      );
      print("Joined channel: $callId");

      // Post-join: ensure mic is active and volume is max
      await Future.delayed(const Duration(milliseconds: 500));
      await _engine!.enableLocalAudio(true);
      await _engine!.muteLocalAudioStream(false);
      await _engine!.adjustRecordingSignalVolume(100);
      await _engine!.adjustPlaybackSignalVolume(100);

      // On web, re-confirm channel options after join to ensure mic track is published
      if (PlatformHelper.isWeb) {
        await _engine!.updateChannelMediaOptions(
          const ChannelMediaOptions(
            publishMicrophoneTrack: true,
            autoSubscribeAudio: true,
          ),
        );
      }
    } catch (e) {
      print("Error joining channel: $e");

      // Web recovery: try with simpler options
      if (PlatformHelper.isWeb) {
        try {
          await _engine!.enableAudio();
          await _engine!.setAudioProfile(
            profile: AudioProfileType.audioProfileSpeechStandard,
            scenario: AudioScenarioType.audioScenarioDefault,
          );
          await Future.delayed(const Duration(milliseconds: 700));

          await _engine!.joinChannel(
            token: '',
            channelId: callId,
            uid: 0,
            options: const ChannelMediaOptions(
              channelProfile: ChannelProfileType.channelProfileCommunication,
              clientRoleType: ClientRoleType.clientRoleBroadcaster,
              publishMicrophoneTrack: true,
              autoSubscribeAudio: true,
            ),
          );
          print("Joined channel with recovery options");
        } catch (recoveryError) {
          print("Web recovery failed: $recoveryError");
          throw Exception("Web call initialization failed after recovery");
        }
      } else {
        // Mobile recovery: minimal options
        try {
          await _engine!.joinChannel(
            token: '',
            channelId: callId,
            uid: 0,
            options: const ChannelMediaOptions(
              channelProfile: ChannelProfileType.channelProfileCommunication,
            ),
          );
          print("Joined channel with fallback options");
        } catch (fallbackError) {
          throw Exception("Failed to join call channel: $fallbackError");
        }
      }
    }
  }

  Future<bool> _requestPermissions(bool isVideoCall) async {
    try {
      if (PlatformHelper.isWeb) {
        try {
          await _ensureWebPermissions();
          return true;
        } catch (e) {
          print("Web permissions error: $e");
          return false;
        }
      } else if (PlatformHelper.isAndroid) {
        PermissionStatus micStatus = await Permission.microphone.request();
        bool hasAudio = micStatus.isGranted;
        bool hasVideo = true;
        if (isVideoCall) {
          PermissionStatus camStatus = await Permission.camera.request();
          hasVideo = camStatus.isGranted;
        }
        return hasAudio && (isVideoCall ? hasVideo : true);
      } else {
        PermissionStatus micStatus = await Permission.microphone.request();
        if (isVideoCall) await Permission.camera.request();
        return micStatus.isGranted;
      }
    } catch (e) {
      print("Error requesting permissions: $e");
      return false;
    }
  }

  /// Request mic permission on web by triggering getUserMedia via Agora SDK.
  /// This MUST be called from a user gesture context (e.g. click handler)
  /// for the browser to show the permission prompt.
  Future<void> _ensureWebPermissions() async {
    if (!PlatformHelper.isWeb) return;
    if (_engine == null) return;
    try {
      // Disable first to reset SDK internal state, then re-enable.
      // This forces Agora to make a fresh getUserMedia call which
      // triggers the browser permission prompt.
      await _engine!.enableLocalAudio(false);
      await Future.delayed(const Duration(milliseconds: 200));
      await _engine!.enableLocalAudio(true);
      await Future.delayed(const Duration(milliseconds: 500));
      print("Web mic permission requested successfully");
    } catch (e) {
      print("Web permission request failed: $e");
      throw Exception("Microphone permission denied or unavailable");
    }
  }

  Future<void> _configureAudioSession(bool isVideoCall) async {
    try {
      if (PlatformHelper.isWeb) {
        await _engine!.enableAudio();
        await _engine!.enableLocalAudio(true);
        await _engine!.setAudioProfile(
          profile: AudioProfileType.audioProfileSpeechStandard,
          scenario: AudioScenarioType.audioScenarioChatroom,
        );
        await _engine!.adjustRecordingSignalVolume(100);
        await _engine!.adjustPlaybackSignalVolume(100);
      } else if (PlatformHelper.isAndroid) {
        await _engine!.enableAudio();
        await _engine!.enableLocalAudio(true);
        await _engine!.setAudioProfile(
          profile: AudioProfileType.audioProfileDefault,
          scenario: AudioScenarioType.audioScenarioDefault,
        );
        await _engine!.adjustRecordingSignalVolume(100);
        await _engine!.adjustPlaybackSignalVolume(100);
      } else {
        await _engine!.enableAudio();
        await _engine!.enableLocalAudio(true);
        await _engine!.setAudioProfile(
          profile: AudioProfileType.audioProfileDefault,
          scenario: AudioScenarioType.audioScenarioDefault,
        );
        await _engine!.adjustRecordingSignalVolume(100);
        await _engine!.adjustPlaybackSignalVolume(100);
        await _engine!.enableAudioVolumeIndication(
          interval: 1000,
          smooth: 3,
          reportVad: true,
        );
      }

      // Common configuration
      await _engine!.setDefaultAudioRouteToSpeakerphone(isVideoCall);

      if (isVideoCall) {
        await _engine!.enableVideo();
        try {
          await _engine!.startPreview();
        } catch (e) {
          print("Preview failed: $e");
        }
      } else {
        await _engine!.disableVideo();
      }
    } catch (e) {
      print("Error configuring audio session: $e");
      rethrow;
    }
  }

  Future<void> _showCallkitIncoming(Call call,
      {required bool isOutgoing}) async {
    if (PlatformHelper.isDesktop || PlatformHelper.isWeb) return;

    try {
      if (isOutgoing) {
        var callKitParams = CallKitParams(
          id: call.callId,
          nameCaller: call.receiverName,
          appName: 'Flutter Chat App',
          avatar: call.receiverPhotoUrl,
          handle: '',
          type: call.isVideo ? 1 : 0,
          duration: 30000,
          textAccept: 'Accept',
          textDecline: 'Decline',
          extra: <String, dynamic>{
            'userId': call.receiverId,
          },
          headers: <String, dynamic>{
            'platform': 'flutter'
          },
          android: const AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#0955fa',
            actionColor: '#4CAF50',
          ),
          ios: const IOSParams(
            iconName: 'CallKitLogo',
            handleType: '',
            supportsVideo: true,
            maximumCallGroups: 2,
            maximumCallsPerCallGroup: 1,
            audioSessionMode: 'voiceChat',
            audioSessionActive: true,
            audioSessionPreferredSampleRate: 44100.0,
            audioSessionPreferredIOBufferDuration: 0.005,
            supportsDTMF: true,
            supportsHolding: true,
            supportsGrouping: false,
            supportsUngrouping: false,
            ringtonePath: 'system_ringtone_default',
          ),
        );
        await FlutterCallkitIncoming.startCall(callKitParams);
      } else {
        var callKitParams = CallKitParams(
          id: call.callId,
          nameCaller: call.callerName,
          appName: 'Flutter Chat App',
          avatar: call.callerPhotoUrl,
          handle: '',
          type: call.isVideo ? 1 : 0,
          duration: 30000,
          textAccept: 'Accept',
          textDecline: 'Decline',
          extra: <String, dynamic>{'userId': call.callerId},
          headers: <String, dynamic>{
            'platform': 'flutter'
          },
          android: const AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#0955fa',
            actionColor: '#4CAF50',
          ),
          ios: const IOSParams(
            iconName: 'CallKitLogo',
            handleType: '',
            supportsVideo: true,
            maximumCallGroups: 2,
            maximumCallsPerCallGroup: 1,
            audioSessionMode: 'voiceChat',
            audioSessionActive: true,
            audioSessionPreferredSampleRate: 44100.0,
            audioSessionPreferredIOBufferDuration: 0.005,
            supportsDTMF: true,
            supportsHolding: true,
            supportsGrouping: false,
            supportsUngrouping: false,
            ringtonePath: 'system_ringtone_default',
          ),
        );
        await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
      }
    } catch (e) {
      print('Error showing CallKit UI: $e');
    }
  }

  Future<void> _updateCallStatus(String status) async {
    if (_currentCall == null) return;
    await _firestore.collection('calls').doc(_currentCall!.callId).update({
      'status': status,
    });
  }

  void dispose() {
    _callTimeoutTimer?.cancel();
    _engine?.release();
    _callStatusController.close();
  }
}
