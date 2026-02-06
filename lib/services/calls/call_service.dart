import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'web_call_helper.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

// You would get this from your Agora.io console
const String agoraAppId =
    'edbb53879a314cc8bd7417e867d4a322'; // Replace with actual Agora app ID

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
  final String status; // 'ringing', 'ongoing', 'ended', 'declined'
  final int? duration; // in seconds, null if call is not ended

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
      'timestamp':
          FieldValue.serverTimestamp(), // Use server timestamp for consistency
      'isVideo': isVideo,
      'status': status,
      'duration': duration,
    };
  }

  factory Call.fromMap(Map<String, dynamic> map) {
    // Safely handle timestamp conversion
    DateTime timestamp;
    if (map['timestamp'] is Timestamp) {
      timestamp = (map['timestamp'] as Timestamp).toDate();
    } else if (map['timestamp'] is DateTime) {
      timestamp = map['timestamp'] as DateTime;
    } else {
      // Default to current time if timestamp is missing or in an unexpected format
      timestamp = DateTime.now();
    }

    return Call(
      callId: map['callId'],
      callerId: map['callerId'],
      receiverId: map['receiverId'],
      callerName: map['callerName'],
      callerPhotoUrl: map['callerPhotoUrl'],
      receiverName: map['receiverName'],
      receiverPhotoUrl: map['receiverPhotoUrl'],
      timestamp: timestamp,
      isVideo: map['isVideo'] ?? false,
      status: map['status'],
      duration: map['duration'],
    );
  }
}

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Agora SDK client
  RtcEngine? _engine;

  // Public getter for the engine
  RtcEngine? get engine => _engine;

  // Stream controllers to notify UI
  final _callStatusController = StreamController<Call>.broadcast();
  
  // Expose the engine for voice call fixing utilities
  RtcEngine? getAgoraEngine() => _engine;
  
  // Fix voice transmission issues
  Future<bool> fixVoiceIssues() async {
    if (_engine == null || _currentCall == null) return false;
    
    print("🔄 Attempting to fix voice transmission issues");
    
    try {
      // Step 1: Reset basic audio state
      await _engine!.enableLocalAudio(false);
      await Future.delayed(const Duration(milliseconds: 500));
      await _engine!.enableLocalAudio(true);
      
      // Step 2: Adjust volume levels to maximum
      await _engine!.adjustRecordingSignalVolume(100); // Max microphone volume
      await _engine!.adjustPlaybackSignalVolume(100);  // Max speaker volume
      
      // Step 3: Apply platform-specific fixes
      if (PlatformHelper.isWeb) {
        print("🌐 Applying comprehensive web-specific voice fixes");
        
        // Apply our enhanced web audio optimizations
        await WebCallHelper.optimizeWebAudioTransmission(_engine!);
        
        // Setup diagnostic listeners to monitor audio state
        await WebCallHelper.setupWebDiagnosticListeners(_engine!);
        
        // Force audio device reset on web
        await _engine!.setParameters("""
        {
          "che.audio.force_use_specific_audio_input": "",
          "che.audio.reset_recording_device": true
        }
        """);
        
        // Reset and update channel media options with explicit track publishing
        await _engine!.updateChannelMediaOptions(
          const ChannelMediaOptions(
            publishMicrophoneTrack: true,
            publishCameraTrack: true,
            autoSubscribeAudio: true,
            autoSubscribeVideo: true,
          ),
        );
      } else {
        // Mobile-specific optimizations
        await _engine!.setAudioProfile(
          profile: AudioProfileType.audioProfileDefault,
          scenario: AudioScenarioType.audioScenarioGameStreaming,
        );
      }
      
      print("✅ Voice issues fix attempt completed");
      return true;
    } catch (e) {
      print("❌ Error fixing voice issues: $e");
      return false;
    }
  }
  Stream<Call> get callStatus => _callStatusController.stream;

  // Track the current call
  Call? _currentCall;
  Call? get currentCall => _currentCall;
  
  // Network adaptivity properties
  Timer? _networkMonitorTimer;
  bool _isNetworkAdaptivityEnabled = true;
  int _lastNetworkRtt = 0;
  double _lastPacketLoss = 0;
  String _networkQuality = 'unknown'; // 'excellent', 'good', 'fair', 'poor'

  // Create a singleton
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  // Verify if the user is authenticated
  bool _isUserAuthenticated() {
    return _auth.currentUser != null;
  }

  // Initialize the Agora SDK
  Future<void> initialize() async {
    if (_engine != null) return;

    // First check if user is authenticated to prevent permission issues
    if (!_isUserAuthenticated()) {
      throw Exception("User must be authenticated to initialize call service");
    }

    try {
      // Request permissions first and check if they were granted
      bool permissionsGranted = await _requestPermissions(false); // Request basic permissions
      
      if (!permissionsGranted) {
        throw Exception("Required permissions were denied");
      }
      
      // Create RTC engine instance with improved error handling
      try {
        print("Creating Agora RTC Engine on platform: ${PlatformHelper.isWeb ? 'WEB' : PlatformHelper.isAndroid ? 'ANDROID' : 'iOS/DESKTOP'}");
        _engine = createAgoraRtcEngine();
        
        // Add platform-specific initialization
        if (PlatformHelper.isWeb) {
          print("🌐 Web platform detected, using web-optimized initialization");
          
          // Special web initialization with additional options
          await _engine!.initialize(const RtcEngineContext(
            appId: agoraAppId,
            channelProfile: ChannelProfileType.channelProfileCommunication,
            // Specify audio scenario explicitly for web
            audioScenario: AudioScenarioType.audioScenarioDefault,
          ));
          
          // Add explicit web audio setup immediately after initialization
          await _engine!.enableAudio();
          print("🌐 Web audio explicitly enabled");
          
          // Add delay for Web SDK to properly initialize
          await Future.delayed(const Duration(milliseconds: 300));
        } else {
          // Standard initialization for mobile/desktop
          await _engine!.initialize(const RtcEngineContext(
            appId: agoraAppId,
            channelProfile: ChannelProfileType.channelProfileCommunication,
          ));
        }

        // Register event handler
        _engine!.registerEventHandler(
          RtcEngineEventHandler(
            onJoinChannelSuccess: (connection, elapsed) {
              print("✅ Local user joined the channel: ${connection.channelId} [${PlatformHelper.isWeb ? 'WEB' : 'MOBILE'}]");
              _updateCallStatus('ongoing');
              
              // Platform-specific optimizations after joining
              if (PlatformHelper.isWeb) {
                // Web-specific: additional setup for ensuring good voice quality
                WebCallHelper.checkAndFixWebAudioDevices(_engine!).then((_) {
                  print("🌐 Web audio device check completed after joining channel");
                  
                  // Extra check to ensure audio is properly set up
                  _engine!.adjustRecordingSignalVolume(100);
                  _engine!.adjustPlaybackSignalVolume(100);
                });
              } else {
                // Mobile optimizations
                _engine!.adjustRecordingSignalVolume(100);
                _engine!.adjustPlaybackSignalVolume(100);
              }
            },
            onUserJoined: (connection, remoteUid, elapsed) {
              print("✅ Remote user joined: $remoteUid [${PlatformHelper.isWeb ? 'WEB' : 'MOBILE'}]");
              // Automatically subscribe to remote audio
              _engine?.muteRemoteAudioStream(uid: remoteUid, mute: false);
              print("🔊 Subscribed to remote audio stream from $remoteUid");
            },
            onUserOffline: (connection, remoteUid, reason) {
              print("⚠️ Remote user left: $remoteUid, reason: $reason");
              if (reason == UserOfflineReasonType.userOfflineQuit) {
                endCall();
              }
            },
            onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
              // Monitor audio levels
              for (var speaker in speakers) {
                if (speaker.uid == 0) {
                  // Local user audio level
                  if ((speaker.volume ?? 0) > 0) {
                    print("🎤 Local audio level: ${speaker.volume} [${PlatformHelper.isWeb ? 'WEB' : 'MOBILE'}]");
                  }
                } else {
                  // Remote user audio level
                  if ((speaker.volume ?? 0) > 0) {
                    print("🔊 Remote audio level from ${speaker.uid}: ${speaker.volume} [${PlatformHelper.isWeb ? 'WEB' : 'MOBILE'}]");
                  }
                }
              }
            },
            onRemoteAudioStateChanged: (connection, remoteUid, state, reason, elapsed) {
              print("🔊 Remote audio state changed - UID: $remoteUid, State: $state, Reason: $reason [${PlatformHelper.isWeb ? 'WEB' : 'MOBILE'}]");
              
              // If remote audio is available, make sure we're not muting it
              if (state == RemoteAudioState.remoteAudioStateDecoding) {
                _engine?.muteRemoteAudioStream(uid: remoteUid, mute: false);
                print("🔊 Ensured remote audio is not muted for UID: $remoteUid");
              }
            },
            onLocalAudioStateChanged: (connection, state, error) {
              print("🎤 Local audio state changed - State: $state, Error: $error [${PlatformHelper.isWeb ? 'WEB' : 'MOBILE'}]");
              
              // Platform-specific error handling for local audio issues
              if (state == LocalAudioStreamState.localAudioStreamStateFailed) {
                print("⚠️ Local audio failed, attempting recovery...");
                // Simple recovery by toggling audio
                _engine?.enableLocalAudio(false);
                Future.delayed(const Duration(milliseconds: 500), () {
                  _engine?.enableLocalAudio(true);
                });
              } else if (state == LocalAudioStreamState.localAudioStreamStateStopped) {
                // Audio may have been stopped due to device switching or permissions
                print("⚠️ Local audio stopped");
                // Attempt to restart audio after a short delay
                Future.delayed(const Duration(seconds: 1), () {
                  _engine?.enableLocalAudio(true);
                });
              }
            },
            onError: (err, msg) {
              print("❌ Agora Error occurred: $err, $msg");
              
              // Handle critical errors with recovery attempt
              // Note: err is of type ErrorCodeType (enum)
              final errorCode = err.index;
              print("⚠️ Error code number: $errorCode");
              
              // Check for serious connection errors
              if (errorCode > 0) {
                print("⚠️ Significant error detected, attempting recovery...");
                _attemptErrorRecovery();
              }
            },
          ),
        );

        print("Agora RTC Engine initialized successfully");
      } catch (e) {
        print("Error initializing main Agora RTC Engine: $e");

        // Add special handling for Windows platform
        if (PlatformHelper.isDesktop) {
          print(
              "Windows/Desktop platform detected. Using alternative initialization.");
          try {
            // Try alternative initialization for Windows
            _engine = createAgoraRtcEngine();
            await Future.delayed(
                const Duration(milliseconds: 500)); // Add delay for Windows

            await _engine!.initialize(const RtcEngineContext(
              appId: agoraAppId,
              // Replace with simpler configuration that doesn't require additional imports
              channelProfile: ChannelProfileType.channelProfileCommunication,
            ));

            print("Alternative Agora initialization successful");
          } catch (desktopError) {
            print("Error in alternative Agora initialization: $desktopError");
            _engine = null;
            rethrow;
          }
        } else {
          _engine = null;
          rethrow;
        }
      }
    } catch (e) {
      print("Error initializing Agora RTC Engine: $e");
      _engine = null;
      rethrow;
    }
  }

  // Check if web browser supports calling
  Future<bool> _checkWebSupport() async {
    if (!PlatformHelper.isWeb) return true; // Non-web is always supported
    
    print("🌐 Checking web browser calling capabilities");
    try {
      // Use WebCallHelper to check browser support
      final hasSupport = WebCallHelper.checkWebSupport();
      
      if (!hasSupport) {
        print("⚠️ Web browser may have limited calling support");
      } else {
        print("✅ Web browser has calling support");
      }
      
      return hasSupport;
    } catch (e) {
      print("❌ Error checking web support: $e");
      return false;
    }
  }
  
  // Start a call to another user
  Future<Call?> startCall(String receiverId, bool isVideoCall) async {
    try {
      // Handle desktop platforms specially
      if (PlatformHelper.isDesktop) {
        print('Call functionality not fully supported on desktop');

        // Get current user
        User? user = _auth.currentUser;
        if (user == null) {
          throw Exception("User is not logged in");
        }

        // Create a mock call for tracking purposes
        String callId =
            'desktop-mock-call-${DateTime.now().millisecondsSinceEpoch}';

        // Get receiver user details if possible
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

        // Create call object for UI purposes
        Call call = Call(
          callId: callId,
          callerId: user.uid,
          receiverId: receiverId,
          callerName: user.displayName ?? 'You',
          receiverName: receiverName,
          timestamp: DateTime.now(),
          isVideo: isVideoCall,
          status: 'desktop-mock',
        );

        // Set current call
        _currentCall = call;
        _callStatusController.add(call);

        return call;
      }
      
      // Web platform pre-checks
      if (PlatformHelper.isWeb) {
        print("🌐 Web call pre-checks: starting web call initialization sequence");
        
        // First check if the browser supports calling
        bool webSupport = await _checkWebSupport();
        if (!webSupport) {
          print("⚠️ Web browser may not fully support calling features");
          // Continue anyway, but log the warning
        }
        
        // Ensure no existing call is in progress
        if (_currentCall != null) {
          print("⚠️ Web call pre-checks: Detected existing call, cleaning up first");
          try {
            await _engine?.leaveChannel();
          } catch (e) {
            print("🌐 Web cleanup of previous call: $e");
          }
          _currentCall = null;
        }
      }

      // Make sure engine is initialized with special handling for web
      if (_engine == null) {
        print("🚨 Engine is null, initializing before starting call");
        await initialize();
        
        // Double check the engine initialization succeeded
        if (_engine == null) {
          throw Exception("Failed to initialize call engine");
        }
        
        // For web, ensure we have a short delay after initialization before starting call
        if (PlatformHelper.isWeb) {
          print("🌐 Web platform: Adding delay after initialization");
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // Continue with normal call flow for mobile platforms
      // Check permissions and handle denial case
      bool permissionsGranted = await _requestPermissions(isVideoCall);
      if (!permissionsGranted) {
        throw Exception("Required call permissions were denied");
      }

      // Get current user
      User? user = _auth.currentUser;
      if (user == null) {
        throw Exception("User is not logged in");
      }

      // Get receiver user details
      DocumentSnapshot receiverDoc =
          await _firestore.collection('users').doc(receiverId).get();
      if (!receiverDoc.exists) {
        throw Exception("Receiver not found");
      }

      Map<String, dynamic> receiverData =
          receiverDoc.data() as Map<String, dynamic>;

      // Get caller user details
      DocumentSnapshot callerDoc =
          await _firestore.collection('users').doc(user.uid).get();
      Map<String, dynamic> callerData =
          callerDoc.data() as Map<String, dynamic>;

      // Create a unique call ID
      String callId = _firestore.collection('calls').doc().id;

      // Create call object
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

      // Save call to Firestore
      await _firestore.collection('calls').doc(callId).set(call.toMap());

      // Set current call
      _currentCall = call;
      _callStatusController.add(call);

      // Show call UI for the caller
      await _showCallkitIncoming(call, isOutgoing: true);

      // Configure Agora
      await _configureAudioSession(isVideoCall);

      // Join the channel with enhanced error handling
      try {
        ChannelMediaOptions channelOptions;
        
        if (PlatformHelper.isWeb) {
          // Enhanced web-specific channel options with more compatibility
          print("🌐 Web: Starting comprehensive web call setup sequence");
          
          // Additional web-specific pre-checks
          if (_engine == null) {
            throw Exception("Engine is null when trying to start web call");
          }
          
          // Ensure audio devices are properly initialized for web
          print("🌐 Web: Checking and initializing audio devices");
          await _engine!.enableAudio();
          await _engine!.enableLocalAudio(true);
          
          // Set audio profile specifically for web
          print("🌐 Web: Configuring audio profile for web call");
          await _engine!.setAudioProfile(
            profile: AudioProfileType.audioProfileDefault,
            scenario: AudioScenarioType.audioScenarioChatroom,
          );
          
          // Add a brief delay for web audio system initialization
          print("🌐 Web: Allowing time for audio system initialization");
          await Future.delayed(const Duration(milliseconds: 300));
          
          // Simplified channel options optimized for web browser compatibility
          print("🌐 Web: Creating optimized channel options for browser");
          channelOptions = const ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileCommunication,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            // Critical for web: be explicit about tracks with minimal options
            publishMicrophoneTrack: true,
            publishCameraTrack: false, 
            autoSubscribeAudio: true,
            autoSubscribeVideo: false,
          );
          
          // Special log for debugging
          print("🌐 Web: Call setup complete, preparing to join channel");
        } else {
          // Mobile/Desktop channel options
          channelOptions = const ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileCommunication,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            publishMicrophoneTrack: true,
            publishCameraTrack: false,
            autoSubscribeAudio: true,
            autoSubscribeVideo: false,
          );
        }
        
        // Add diagnostics before attempting to join
        print("🚀 Attempting to join channel: $callId with uid: 0");
        print("📊 Engine state check: initialized=${_engine != null}");
        
        // For web, add additional diagnostics right before joining
        if (PlatformHelper.isWeb) {
          print("🌐 Web: Final channel join preparation for channel: $callId");
        }
        
        await _engine!.joinChannel(
          token: '', // Use empty string instead of null
          channelId: callId,
          uid: 0, // 0 means let Agora assign one
          options: channelOptions,
        );
        
        print("✅ Successfully joined channel: $callId for ${PlatformHelper.isWeb ? 'web' : 'mobile/desktop'}");
      } catch (e) {
        print("❌ Error joining Agora channel: $e");
        
        // Special handling for web platform with enhanced recovery
        if (PlatformHelper.isWeb) {
          print("🌐 Web: Initiating multi-stage web recovery procedure");
          
          try {
            // Stage 1: Reset audio state and try again
            print("🌐 Web Recovery Stage 1: Resetting audio system");
            await _engine!.enableAudio();
            await _engine!.setAudioProfile(
              profile: AudioProfileType.audioProfileSpeechStandard,
              scenario: AudioScenarioType.audioScenarioDefault,
            );
            await Future.delayed(const Duration(milliseconds: 700));
            
            print("🌐 Web Recovery Stage 1: Attempting join with reset audio");
            await _engine!.joinChannel(
              token: '',
              channelId: callId,
              uid: 0,
              options: const ChannelMediaOptions(
                // Minimal options for web
                channelProfile: ChannelProfileType.channelProfileCommunication,
                clientRoleType: ClientRoleType.clientRoleBroadcaster,
                publishMicrophoneTrack: true,
                autoSubscribeAudio: true,
              ),
            );
            
            print("✅ Web Recovery Stage 1 successful!");
          } catch (stageOneError) {
            print("❌ Web Recovery Stage 1 failed: $stageOneError");
            
            // Stage 2: Try with absolute minimal configuration
            try {
              print("🌐 Web Recovery Stage 2: Using minimal configuration");
              
              // Use a different UID to avoid conflicts
              const int alternativeUid = 1000;
              print("🌐 Web Recovery Stage 2: Using alternative UID: $alternativeUid");
              
              await _engine!.joinChannel(
                token: '',
                channelId: callId,
                uid: alternativeUid,
                options: const ChannelMediaOptions(
                  // Absolutely minimal options
                  channelProfile: ChannelProfileType.channelProfileCommunication,
                ),
              );
              
              print("✅ Web Recovery Stage 2 successful!");
            } catch (stageTwoError) {
              print("❌ Web Recovery Stage 2 failed: $stageTwoError");
              
              // Log detailed browser information for debugging
              print("🌐 Web diagnostics:");
              print("🌐 URL: ${Uri.base}");
              print("🌐 Call ID: $callId");
              
              // Throw a more descriptive error for the UI
              throw Exception("Web call initialization failed after recovery attempts");
            }
          }
        } else {
          // Non-web recovery: Try with simplified options
          try {
            await _engine!.joinChannel(
              token: '',
              channelId: callId,
              uid: 0,
              options: const ChannelMediaOptions(
                channelProfile: ChannelProfileType.channelProfileCommunication,
              ),
            );
            print("✅ Joined channel with fallback options");
          } catch (fallbackError) {
            print("❌ Error joining Agora channel with fallback options: $fallbackError");
            throw Exception("Failed to join call channel: $fallbackError");
          }
        }
      }

      return call;
    } catch (e) {
      print("Error starting call: $e");
      return null;
    }
  }

  // Answer an incoming call
  Future<bool> answerCall(String callId) async {
    try {
      // Get call details
      DocumentSnapshot callDoc =
          await _firestore.collection('calls').doc(callId).get();
      if (!callDoc.exists) {
        throw Exception("Call not found");
      }

      Call call = Call.fromMap(callDoc.data() as Map<String, dynamic>);

      // Make sure engine is initialized
      if (_engine == null) {
        await initialize();
      }

      // Check permissions with proper handling
      bool permissionsGranted = await _requestPermissions(call.isVideo);
      if (!permissionsGranted) {
        print("❌ Permission denied when answering call");
        throw Exception("Required permissions were denied for answering call");
      }

      // Set current call
      _currentCall = call;
      _callStatusController.add(call);

      // Update call status
      await _firestore.collection('calls').doc(callId).update({
        'status': 'ongoing',
      });

      // Configure audio session
      await _configureAudioSession(call.isVideo);

      // Join the channel with error handling
      try {
        ChannelMediaOptions channelOptions;
        
        if (PlatformHelper.isWeb) {
          // Web-specific channel options for answering call
          channelOptions = const ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileCommunication,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            publishMicrophoneTrack: true,
            publishCameraTrack: false,
            autoSubscribeAudio: true,
            autoSubscribeVideo: false,
          );
        } else {
          // Mobile/Desktop channel options for answering call
          channelOptions = const ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileCommunication,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            publishMicrophoneTrack: true,
            publishCameraTrack: false,
            autoSubscribeAudio: true,
            autoSubscribeVideo: false,
          );
        }
        
        await _engine!.joinChannel(
          token: '', // Generate token on server in production
          channelId: callId,
          uid: 0, // 0 means let Agora assign one
          options: channelOptions,
        );
        
        print("✅ Successfully answered and joined channel: $callId for ${PlatformHelper.isWeb ? 'web' : 'mobile/desktop'}");
      } catch (e) {
        print("❌ Error joining Agora channel during answer: $e");
        // Try with alternative configuration if the first attempt fails
        try {
          await _engine!.joinChannel(
            token: '',
            channelId: callId,
            uid: 0,
            options: const ChannelMediaOptions(
              channelProfile: ChannelProfileType.channelProfileCommunication,
            ),
          );
          print("✅ Answered call with fallback options");
        } catch (e) {
          print("❌ Error joining Agora channel with fallback options: $e");
          throw Exception("Failed to join call channel: $e");
        }
      }

      return true;
    } catch (e) {
      print("Error answering call: $e");
      return false;
    }
  }

  // End or decline a call
  Future<void> endCall({bool isDeclined = false}) async {
    if (_currentCall == null) return;

    try {
      // Leave the channel
      await _engine?.leaveChannel();

      // Calculate call duration
      int? duration;
      if (_currentCall!.status == 'ongoing') {
        duration = DateTime.now().difference(_currentCall!.timestamp).inSeconds;
      }

      // Update call in Firestore
      await _firestore.collection('calls').doc(_currentCall!.callId).update({
        'status': isDeclined ? 'declined' : 'ended',
        'duration': duration,
      });

      // End CallKit UI
      await FlutterCallkitIncoming.endAllCalls();

      // Get updated call data
      DocumentSnapshot callDoc =
          await _firestore.collection('calls').doc(_currentCall!.callId).get();
      Call updatedCall = Call.fromMap(callDoc.data() as Map<String, dynamic>);

      // Notify listeners
      _callStatusController.add(updatedCall);

      // Clear current call
      _currentCall = null;
    } catch (e) {
      print("Error ending call: $e");
    }
  }

  // Toggle mute status
  bool _isMuted = false;
  
  Future<bool> toggleMute() async {
    if (_engine == null) return false;

    try {
      // Toggle the mute state
      _isMuted = !_isMuted;
      
      // Apply the mute state to the local audio stream
      await _engine!.muteLocalAudioStream(_isMuted);
      
      // Also adjust recording volume for better control
      await _engine!.adjustRecordingSignalVolume(_isMuted ? 0 : 100);
      
      print("🎤 Microphone ${_isMuted ? 'muted' : 'unmuted'}");
      
      return _isMuted;
    } catch (e) {
      print("❌ Error toggling mute: $e");
      return _isMuted;
    }
  }

  // Toggle speaker
  Future<bool> toggleSpeaker() async {
    if (_engine == null) return false;

    try {
      // Using the correct API methods for RtcEngine
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
    if (user == null) {
      throw Exception("User is not logged in");
    }

    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        Call call = Call.fromMap(snapshot.docs.first.data());
        _currentCall = call;

        // Show incoming call UI
        _showCallkitIncoming(call, isOutgoing: false);
        return call;
      }
      // Return an empty stream instead of throwing an exception
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
      // Return a placeholder call on error
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

        if (call.status == 'declined' || call.status == 'ended') {
          // End the call UI
          FlutterCallkitIncoming.endAllCalls();
          _engine?.leaveChannel();
          _currentCall = null;
        }

        return call;
      }
      // Return a placeholder call instead of throwing an exception
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
      // Return a placeholder call on error
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

  // Private helper methods
  Future<bool> _requestPermissions(bool isVideoCall) async {
    try {
      if (PlatformHelper.isWeb) {
        print("🌐 Requesting web browser permissions");
        // For web, we need to actively ensure permissions are properly requested
        // Create a function to trigger browser permission prompts explicitly
        try {
          // This will trigger browser permission dialog
          await _ensureWebPermissions();
          print("✅ Web permissions handling completed");
          return true;
        } catch (e) {
          print("❌ Web permissions error: $e");
          return false;
        }
      } else if (PlatformHelper.isAndroid) {
        print("🤖 Requesting Android permissions");
        // Android requires explicit permission requests
        PermissionStatus micStatus = await Permission.microphone.request();
        bool hasAudio = micStatus.isGranted;
        
        bool hasVideo = true;
        if (isVideoCall) {
          PermissionStatus camStatus = await Permission.camera.request();
          hasVideo = camStatus.isGranted;
        }
        
        // Check if we have necessary permissions
        bool hasRequiredPermissions = hasAudio && (isVideoCall ? hasVideo : true);
        if (!hasRequiredPermissions) {
          print("❌ Missing required Android permissions");
        }
        
        return hasRequiredPermissions;
      } else {
        print("📱 Requesting iOS/desktop permissions");
        // Standard permission request for iOS/desktop
        PermissionStatus micStatus = await Permission.microphone.request();
        if (isVideoCall) {
          await Permission.camera.request();
        }
        
        return micStatus.isGranted;
      }
    } catch (e) {
      print("❌ Error requesting permissions: $e");
      return false;
    }
  }
  
  // Helper to ensure web permissions are properly requested
  Future<void> _ensureWebPermissions() async {
    if (!PlatformHelper.isWeb) return;
    
    try {
      print("🌐 Ensuring web permissions are properly requested");
      // This will trigger the browser's permission dialog
      await _engine?.enableLocalAudio(true);
      
      // Short delay to allow browser to process permission
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print("❌ Web permission request failed: $e");
      throw Exception("Web permission request failed: $e");
    }
  }

  Future<void> _configureAudioSession(bool isVideoCall) async {
    try {
      // Platform-specific audio configuration based on device type
      if (PlatformHelper.isWeb) {
        print("🌐 Configuring enhanced audio for web platform with voice optimization");
        
        // Enable audio subsystem
        await _engine!.enableAudio();
        
        // For web, we need to explicitly enable local audio capture
        await _engine!.enableLocalAudio(true);
        
        // Use our enhanced WebCallHelper for optimal voice transmission
        await WebCallHelper.optimizeWebAudioTransmission(_engine!);
        
        print("🌐 Web voice transmission optimized for better call quality");
        
        // Extra check to ensure microphone is publishing correctly
        await _engine!.adjustRecordingSignalVolume(100); // Max microphone volume
        await _engine!.adjustPlaybackSignalVolume(100);  // Max speaker volume
        
        print("✅ Web audio configuration completed");
      } else if (PlatformHelper.isAndroid) {
        // Android-specific configuration
        print("🤖 Configuring audio for Android platform");
        
        // Enable audio subsystem with Android-specific settings
        await _engine!.enableAudio();
        await _engine!.enableLocalAudio(true);
        
        // Android-optimized audio profile
        await _engine!.setAudioProfile(
          profile: AudioProfileType.audioProfileDefault,
          scenario: AudioScenarioType.audioScenarioGameStreaming,
        );
        
        print("✅ Android audio configuration completed");
      } else {
        // iOS/Desktop configuration
        print("📱 Configuring audio for iOS/desktop platform");
        
        // Enable audio subsystem
        await _engine!.enableAudio();
        
        // Enable local audio capture (microphone)
        await _engine!.enableLocalAudio(true);
        
        // Set audio profile for high quality audio
        await _engine!.setAudioProfile(
          profile: AudioProfileType.audioProfileDefault,
          scenario: AudioScenarioType.audioScenarioDefault,
        );
        
        // Enable audio volume indication to monitor audio levels
        await _engine!.enableAudioVolumeIndication(
          interval: 1000,
          smooth: 3,
          reportVad: true,
        );
      }
      
      // Common configuration for all platforms
      // Set default audio route
      await _engine!.setDefaultAudioRouteToSpeakerphone(isVideoCall);
      
        // For video calls, enable video with platform-specific handling
      if (isVideoCall) {
        await _engine!.enableVideo();
        // Start preview for all platforms - web now supported with modified config
        if (PlatformHelper.isWeb) {
          // Web requires special handling for video preview
          try {
            print("🌐 Starting web video preview with specific settings");
            await _engine!.startPreview();
            print("✅ Web preview started successfully");
          } catch (e) {
            print("⚠️ Web preview failed but continuing: $e");
            // Continue without preview on web if it fails
          }
        } else {
          // Mobile/desktop preview
          await _engine!.startPreview();
        }
      } else {
        await _engine!.disableVideo();
      }
      
      // Start network monitoring and adaptivity
      _startNetworkMonitoring();
      
      print("✅ Audio session configured successfully for ${PlatformHelper.isWeb ? 'web' : 'mobile/desktop'}");
          } catch (e) {
      print("❌ Error configuring audio session: $e");
      rethrow;
    }
  }

  Future<void> _showCallkitIncoming(Call call,
      {required bool isOutgoing}) async {
    // Skip CallKit on desktop platforms
    if (PlatformHelper.isDesktop) {
      print('CallKit UI skipped on desktop platform');
      return;
    }

    try {
      if (isOutgoing) {
        // Show outgoing call UI
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
            'missedCallText': 'Missed call',
            'callbackText': 'Call back'
          },
          headers: <String, dynamic>{
            'apiKey': 'Abc@123!',
            'platform': 'flutter'
          },
          android: const AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#0955fa',
            backgroundUrl: 'assets/images/call_bg_light.png',
            actionColor: '#4CAF50',
          ),
          ios: const IOSParams(
            iconName: 'CallKitLogo',
            handleType: '',
            supportsVideo: true,
            maximumCallGroups: 2,
            maximumCallsPerCallGroup: 1,
            audioSessionMode: 'default',
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
        // Show incoming call UI
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
            'apiKey': 'Abc@123!',
            'platform': 'flutter'
          },
          android: const AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#0955fa',
            backgroundUrl: 'assets/images/call_bg_light.png',
            actionColor: '#4CAF50',
          ),
          ios: const IOSParams(
            iconName: 'CallKitLogo',
            handleType: '',
            supportsVideo: true,
            maximumCallGroups: 2,
            maximumCallsPerCallGroup: 1,
            audioSessionMode: 'default',
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
      // Continue with the call even if CallKit UI fails
      // This allows calls to work even if the UI part fails
    }
  }

  // Update current call status
  Future<void> _updateCallStatus(String status) async {
    if (_currentCall == null) return;
    await _firestore.collection('calls').doc(_currentCall!.callId).update({
      'status': status,
    });
  }

  // Check if audio is working properly based on internal state
  bool isAudioWorking() {
    if (_engine == null || _currentCall == null) return false;
    
    // This is a basic implementation - in a real app, you would track more state
    // such as audio device connection events, audio level metrics, etc.
    try {
      // Consider audio as working if:
      // 1. We have an active call
      // 2. The call status is "ongoing"
      // 3. The engine is initialized
      return _currentCall?.status == 'ongoing' && _engine != null;
    } catch (e) {
      print("Error checking audio status: $e");
      return false;
    }
  }

  // Dispose resources
  void dispose() {
    _stopNetworkMonitoring();
    _engine?.release();
    _callStatusController.close();
  }
  
  // Network monitoring and adaptivity methods
  
  /// Start monitoring network conditions and adapting call settings
  void _startNetworkMonitoring() {
    // Cancel any existing timer
    _stopNetworkMonitoring();
    
    // Start a new monitoring cycle
    _networkMonitorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkNetworkCondition();
    });
    
    print("🔄 Network monitoring started");
  }
  
  /// Stop network monitoring
  void _stopNetworkMonitoring() {
    _networkMonitorTimer?.cancel();
    _networkMonitorTimer = null;
  }
  
  /// Check network conditions and adapt settings if necessary
  Future<void> _checkNetworkCondition() async {
    if (_engine == null || _currentCall == null) return;
    
    try {
      // For network quality monitoring, we'll use simpler approximations
      // since direct stats access varies by Agora SDK version
      
      // Use a simpler approach with fixed thresholds based on general observations
      // In a real implementation, you would implement platform-specific quality checks
      
      // Simulating network quality assessment
      // In production code, use appropriate Agora SDK methods for your version
      String previousQuality = _networkQuality;
      
      // Simple quality assessment approach
      if (PlatformHelper.isWeb) {
        // Web platform has different network characteristics
        // For now, assume reasonable quality unless we detect issues
        _networkQuality = 'good';
        // In real implementation, check for WebRTC stats
      } else {
        // For mobile platforms, we'd check more detailed stats
        // This is a placeholder that would use actual metrics in production
        _networkQuality = 'good';
      }
      
      // Log network conditions (only when they change)
      if (previousQuality != _networkQuality) {
        print("📊 Network quality: $_networkQuality (RTT: $_lastNetworkRtt ms, Loss: ${(_lastPacketLoss * 100).toStringAsFixed(1)}%)");
      }
      
      // Adapt to network conditions if needed
      if (_isNetworkAdaptivityEnabled) {
        _adaptToNetworkQuality(_networkQuality);
      }
    } catch (e) {
      print("⚠️ Error checking network condition: $e");
    }
  }
  
  /// Adapt call settings based on network quality
  Future<void> _adaptToNetworkQuality(String quality) async {
    if (_engine == null) return;
    
    try {
      switch (quality) {
        case 'excellent':
        case 'good':
          // For excellent/good quality, use optimal settings
          if (PlatformHelper.isWeb) {
            await _engine!.setAudioProfile(
              profile: AudioProfileType.audioProfileMusicStandard,
              scenario: AudioScenarioType.audioScenarioGameStreaming,
            );
          }
          break;
          
        case 'fair':
          // For fair quality, reduce quality slightly
          if (PlatformHelper.isWeb) {
            await _engine!.setAudioProfile(
              profile: AudioProfileType.audioProfileSpeechStandard,
              scenario: AudioScenarioType.audioScenarioDefault,
            );
          }
          break;
          
        case 'poor':
          // For poor quality, use minimum bandwidth settings
          await _engine!.setAudioProfile(
            profile: AudioProfileType.audioProfileSpeechStandard,
            scenario: AudioScenarioType.audioScenarioDefault,
          );
          
          // Platform-specific adaptations
          if (PlatformHelper.isWeb) {
            // Reduce audio processing for web
            await _engine!.enableAudioVolumeIndication(
              interval: 2000, // Reduce frequency
              smooth: 5,
              reportVad: false, // Disable voice activity detection
            );
          }
          
          print("⚠️ Applied low-bandwidth optimizations due to poor network");
          break;
      }
    } catch (e) {
      print("⚠️ Error adapting to network quality: $e");
    }
  }
  
  /// Attempt to recover from errors with platform-specific strategies
  Future<void> _attemptErrorRecovery() async {
    if (_engine == null || _currentCall == null) return;
    
    print("🔄 Attempting error recovery for platform: ${PlatformHelper.isWeb ? 'WEB' : PlatformHelper.isAndroid ? 'ANDROID' : 'iOS/DESKTOP'}");
    
    try {
      // Platform-specific recovery strategies
      if (PlatformHelper.isWeb) {
        print("🌐 Web platform recovery procedure - using enhanced WebCallHelper");
        
        // Use our specialized web call helper for a more comprehensive recovery
        final channelId = _currentCall!.callId;
        final webRecovered = await WebCallHelper.attemptWebCallRecovery(
          _engine, 
          channelId,
          1  // Start with first retry
        );
        
        if (webRecovered) {
          print("✅ Web recovery successful using WebCallHelper");
        } else {
          print("⚠️ WebCallHelper recovery failed, falling back to basic recovery");
          
          // For web, we need to take special care with audio setup
          await _engine!.enableLocalAudio(false);
          await Future.delayed(const Duration(milliseconds: 500));
          await _engine!.enableLocalAudio(true);
          
          // Re-apply web-specific audio configuration
          await _engine!.setAudioProfile(
            profile: AudioProfileType.audioProfileSpeechStandard,
            scenario: AudioScenarioType.audioScenarioDefault,
          );
          
          // Enable audio volume indication with web-optimized settings
          await _engine!.enableAudioVolumeIndication(
            interval: 500,
            smooth: 3,
            reportVad: true,
          );
        }
        
      } else if (PlatformHelper.isAndroid) {
        print("🤖 Android platform recovery procedure");
        
        // For Android, we may need to reset audio routing
        await _engine!.enableLocalAudio(false);
        await Future.delayed(const Duration(milliseconds: 800));
        await _engine!.enableLocalAudio(true);
        
        // Try to reset audio route
        final isVideo = _currentCall!.isVideo;
        await _engine!.setDefaultAudioRouteToSpeakerphone(isVideo);
        
        // Re-apply Android-specific audio settings
        await _engine!.setAudioProfile(
          profile: AudioProfileType.audioProfileDefault,
          scenario: AudioScenarioType.audioScenarioGameStreaming,
        );
        
      } else {
        print("📱 iOS/Desktop platform recovery procedure");
        
        // Generic recovery for other platforms
        await _engine!.enableLocalAudio(false);
        await Future.delayed(const Duration(milliseconds: 500));
        await _engine!.enableLocalAudio(true);
      }
      
      print("✅ Error recovery attempt completed");
    } catch (e) {
      print("❌ Error during recovery attempt: $e");
    }
  }
}
