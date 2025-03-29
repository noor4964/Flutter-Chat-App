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

// You would get this from your Agora.io console
const String agoraAppId =
    'c53972eb0c684391a723191a081abe69'; // Replace with actual Agora app ID

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
  Stream<Call> get callStatus => _callStatusController.stream;

  // Track the current call
  Call? _currentCall;
  Call? get currentCall => _currentCall;

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
      // Request permissions first
      await _requestPermissions(false); // Request basic permissions

      // Create RTC engine instance with improved error handling
      try {
        _engine = createAgoraRtcEngine();
        await _engine!.initialize(const RtcEngineContext(
          appId: agoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ));

        // Register event handler
        _engine!.registerEventHandler(
          RtcEngineEventHandler(
            onJoinChannelSuccess: (connection, elapsed) {
              print("Local user joined the channel: ${connection.channelId}");
              _updateCallStatus('ongoing');
            },
            onUserJoined: (connection, remoteUid, elapsed) {
              print("Remote user joined: $remoteUid");
            },
            onUserOffline: (connection, remoteUid, reason) {
              print("Remote user left: $remoteUid, reason: $reason");
              if (reason == UserOfflineReasonType.userOfflineQuit) {
                endCall();
              }
            },
            onError: (err, msg) {
              print("Error occurred: $err, $msg");
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

      // Make sure engine is initialized
      if (_engine == null) {
        await initialize();
      }

      // Continue with normal call flow for mobile platforms
      // Check permissions
      await _requestPermissions(isVideoCall);

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

      // Join the channel with error handling
      try {
        await _engine!.joinChannel(
          token: '', // Use empty string instead of null
          channelId: callId,
          uid: 0, // 0 means let Agora assign one
          options: const ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
          ),
        );
      } catch (e) {
        print("Error joining Agora channel: $e");
        // Try with alternative configuration if the first attempt fails
        try {
          await _engine!.joinChannel(
            token: '',
            channelId: callId,
            uid: 0,
            options: const ChannelMediaOptions(),
          );
        } catch (e) {
          print("Error joining Agora channel with fallback options: $e");
          throw Exception("Failed to join call channel: $e");
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

      // Check permissions
      await _requestPermissions(call.isVideo);

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
        await _engine!.joinChannel(
          token: '', // Generate token on server in production
          channelId: callId,
          uid: 0, // 0 means let Agora assign one
          options: const ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
          ),
        );
      } catch (e) {
        print("Error joining Agora channel during answer: $e");
        // Try with alternative configuration if the first attempt fails
        try {
          await _engine!.joinChannel(
            token: '',
            channelId: callId,
            uid: 0,
            options: const ChannelMediaOptions(),
          );
        } catch (e) {
          print("Error joining Agora channel with fallback options: $e");
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
  Future<bool> toggleMute() async {
    if (_engine == null) return false;

    try {
      // Using the correct API methods for RtcEngine
      bool isMuted = (await _engine!.getAudioMixingPlayoutVolume() == 0);
      await _engine!.muteLocalAudioStream(!isMuted);
      return !isMuted;
    } catch (e) {
      print("Error toggling mute: $e");
      return false;
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
  Future<void> _requestPermissions(bool isVideoCall) async {
    await Permission.microphone.request();
    if (isVideoCall) {
      await Permission.camera.request();
    }
  }

  Future<void> _configureAudioSession(bool isVideoCall) async {
    await _engine!.enableAudio();
    await _engine!.setDefaultAudioRouteToSpeakerphone(isVideoCall);

    if (isVideoCall) {
      await _engine!.enableVideo();
      await _engine!.startPreview();
    } else {
      await _engine!.disableVideo();
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

  // Dispose resources
  void dispose() {
    _engine?.release();
    _callStatusController.close();
  }
}
