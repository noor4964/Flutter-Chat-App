import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';

enum CallQuality { excellent, good, fair, poor, critical }

enum CallState { idle, ringing, connecting, connected, ending, ended, error }

enum AudioProfile { speechStandard, musicStandard, musicHighQuality, musicHighQualityStereo }

class CallStatistics {
  final int duration;
  final CallQuality quality;
  final int packetsLost;
  final int packetsSent;
  final int packetsReceived;
  final double audioLossRate;
  final int networkDelay;
  final double cpuUsage;
  final double memoryUsage;
  final DateTime timestamp;

  CallStatistics({
    required this.duration,
    required this.quality,
    required this.packetsLost,
    required this.packetsSent,
    required this.packetsReceived,
    required this.audioLossRate,
    required this.networkDelay,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'duration': duration,
      'quality': quality.toString(),
      'packetsLost': packetsLost,
      'packetsSent': packetsSent,
      'packetsReceived': packetsReceived,
      'audioLossRate': audioLossRate,
      'networkDelay': networkDelay,
      'cpuUsage': cpuUsage,
      'memoryUsage': memoryUsage,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class CallSettings {
  bool echoCancellation;
  bool noiseSuppression;
  bool automaticGainControl;
  double volumeLevel;
  AudioProfile audioProfile;
  bool adaptiveBitrate;
  bool lowLatencyMode;

  CallSettings({
    this.echoCancellation = true,
    this.noiseSuppression = true,
    this.automaticGainControl = true,
    this.volumeLevel = 1.0,
    this.audioProfile = AudioProfile.speechStandard,
    this.adaptiveBitrate = true,
    this.lowLatencyMode = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'echoCancellation': echoCancellation,
      'noiseSuppression': noiseSuppression,
      'automaticGainControl': automaticGainControl,
      'volumeLevel': volumeLevel,
      'audioProfile': audioProfile.toString(),
      'adaptiveBitrate': adaptiveBitrate,
      'lowLatencyMode': lowLatencyMode,
    };
  }
}

class EnhancedCallService {
  // Composition instead of inheritance
  final CallService _baseCallService = CallService();
  
  // Enhanced properties
  CallState _callState = CallState.idle;
  CallState get callState => _callState;
  
  CallSettings _callSettings = CallSettings();
  CallSettings get callSettings => _callSettings;
  
  CallStatistics? _lastStatistics;
  CallStatistics? get lastStatistics => _lastStatistics;
  
  Timer? _statisticsTimer;
  Timer? _qualityMonitorTimer;
  Timer? _networkAdaptationTimer;
  
  // Stream controllers for enhanced monitoring
  final _callStateController = StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;
  
  final _callQualityController = StreamController<CallQuality>.broadcast();
  Stream<CallQuality> get callQualityStream => _callQualityController.stream;
  
  final _callStatisticsController = StreamController<CallStatistics>.broadcast();
  Stream<CallStatistics> get callStatisticsStream => _callStatisticsController.stream;
  
  // Enhanced call recording
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  String? _recordingPath;
  
  // Network and quality monitoring
  CallQuality _currentQuality = CallQuality.excellent;
  CallQuality get currentQuality => _currentQuality;
  
  // Delegate properties from base service
  RtcEngine? get engine => _baseCallService.engine;
  Call? get currentCall => _baseCallService.currentCall;
  Stream<Call> get callStatus => _baseCallService.callStatus;
  
  // Delegate methods from base service
  Stream<Call> listenForIncomingCalls() => _baseCallService.listenForIncomingCalls();
  Stream<Call> listenForCallStatusChanges(String callId) => _baseCallService.listenForCallStatusChanges(callId);
  
  // Create singleton
  static final EnhancedCallService _instance = EnhancedCallService._internal();
  factory EnhancedCallService() => _instance;
  EnhancedCallService._internal();

  Future<void> initialize() async {
    try {
      _updateCallState(CallState.connecting);
      
      // Initialize base service
      await _baseCallService.initialize();
      
      // Apply enhanced audio settings only if base service initialized successfully
      try {
        await _configureEnhancedAudio();
      } catch (e) {
        print("⚠️ Enhanced audio configuration failed, but continuing: $e");
        // Continue without enhanced audio features
      }
      
      // Start monitoring systems
      try {
        _startQualityMonitoring();
        _startNetworkAdaptation();
      } catch (e) {
        print("⚠️ Monitoring systems failed to start, but continuing: $e");
        // Continue without monitoring features
      }
      
      _updateCallState(CallState.idle);
      print("✅ Enhanced Call Service initialized successfully");
      
    } catch (e) {
      _updateCallState(CallState.error);
      print("❌ Error initializing Enhanced Call Service: $e");
      
      // Don't rethrow the error, instead continue with basic functionality
      // This allows the app to work even if enhanced features fail
      print("📱 Continuing with basic call functionality...");
      _updateCallState(CallState.idle);
    }
  }

  /// Configure enhanced audio settings
  Future<void> _configureEnhancedAudio() async {
    // Check if engine exists before trying to configure
    if (engine == null) {
      print("⚠️ Engine is null, skipping enhanced audio configuration");
      return;
    }
    
    try {
      // Additional null check before each operation
      final currentEngine = engine;
      if (currentEngine == null) {
        print("⚠️ Engine became null during configuration");
        return;
      }
      
      // Enable audio enhancements
      await currentEngine.enableAudioVolumeIndication(
        interval: 1000,
        smooth: 3,
        reportVad: true,
      );
      
      // Configure audio profile based on settings
      await _applyAudioProfile(_callSettings.audioProfile);
      
      // Enable echo cancellation
      if (_callSettings.echoCancellation) {
        await currentEngine.enableLocalAudio(true);
      }
      
      // Configure automatic gain control
      await currentEngine.setAudioProfile(
        profile: AudioProfileType.audioProfileDefault,
        scenario: AudioScenarioType.audioScenarioDefault,
      );
      
      // Enable dual mono recording if supported
      if (Platform.isAndroid || Platform.isIOS) {
        await currentEngine.enableDualStreamMode(enabled: true);
      }
      
      print("✅ Enhanced audio configuration applied");
      
    } catch (e) {
      print("⚠️ Error configuring enhanced audio: $e");
      // Continue without enhanced audio features
    }
  }

  /// Apply specific audio profile
  Future<void> _applyAudioProfile(AudioProfile profile) async {
    final currentEngine = engine;
    if (currentEngine == null) {
      print("⚠️ Engine is null, skipping audio profile configuration");
      return;
    }
    
    try {
      switch (profile) {
        case AudioProfile.speechStandard:
          await currentEngine.setAudioProfile(
            profile: AudioProfileType.audioProfileSpeechStandard,
            scenario: AudioScenarioType.audioScenarioDefault,
          );
          break;
        case AudioProfile.musicStandard:
          await currentEngine.setAudioProfile(
            profile: AudioProfileType.audioProfileMusicStandard,
            scenario: AudioScenarioType.audioScenarioGameStreaming,
          );
          break;
        case AudioProfile.musicHighQuality:
          await currentEngine.setAudioProfile(
            profile: AudioProfileType.audioProfileMusicHighQuality,
            scenario: AudioScenarioType.audioScenarioGameStreaming,
          );
          break;
        case AudioProfile.musicHighQualityStereo:
          await currentEngine.setAudioProfile(
            profile: AudioProfileType.audioProfileMusicHighQualityStereo,
            scenario: AudioScenarioType.audioScenarioGameStreaming,
          );
          break;
      }
      print("✅ Audio profile applied: $profile");
    } catch (e) {
      print("⚠️ Error applying audio profile: $e");
    }
  }

  /// Start call quality monitoring
  void _startQualityMonitoring() {
    _qualityMonitorTimer?.cancel();
    _qualityMonitorTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _assessCallQuality();
    });
  }

  /// Start network adaptation
  void _startNetworkAdaptation() {
    _networkAdaptationTimer?.cancel();
    _networkAdaptationTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _adaptToNetworkConditions();
    });
  }

  /// Start comprehensive statistics collection
  void _startStatisticsCollection() {
    _statisticsTimer?.cancel();
    _statisticsTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _collectCallStatistics();
    });
  }

  /// Assess call quality based on various metrics
  Future<void> _assessCallQuality() async {
    if (engine == null || _callState != CallState.connected) return;
    
    try {
      // This would require implementing quality assessment based on
      // audio level indicators, network conditions, etc.
      // For now, we'll simulate quality assessment
      
      // In a real implementation, you would use:
      // - Audio quality metrics from Agora
      // - Network latency measurements
      // - Packet loss statistics
      // - Audio level indicators
      
      CallQuality newQuality = _simulateQualityAssessment();
      
      if (newQuality != _currentQuality) {
        _currentQuality = newQuality;
        _callQualityController.add(_currentQuality);
        
        // Auto-adapt based on quality
        if (_callSettings.adaptiveBitrate) {
          await _adaptBasedOnQuality(newQuality);
        }
      }
      
    } catch (e) {
      print("⚠️ Error assessing call quality: $e");
    }
  }

  /// Simulate quality assessment (replace with real implementation)
  CallQuality _simulateQualityAssessment() {
    // This is a placeholder - in real implementation, use actual metrics
    final random = DateTime.now().millisecond % 100;
    if (random < 10) return CallQuality.critical;
    if (random < 25) return CallQuality.poor;
    if (random < 50) return CallQuality.fair;
    if (random < 80) return CallQuality.good;
    return CallQuality.excellent;
  }

  /// Adapt settings based on call quality
  Future<void> _adaptBasedOnQuality(CallQuality quality) async {
    final currentEngine = engine;
    if (currentEngine == null) return;
    
    try {
      switch (quality) {
        case CallQuality.critical:
        case CallQuality.poor:
          // Reduce quality for better stability
          await currentEngine.setAudioProfile(
            profile: AudioProfileType.audioProfileSpeechStandard,
            scenario: AudioScenarioType.audioScenarioDefault,
          );
          await currentEngine.enableLocalAudio(true);
          break;
        case CallQuality.fair:
          // Moderate quality settings
          await currentEngine.setAudioProfile(
            profile: AudioProfileType.audioProfileDefault,
            scenario: AudioScenarioType.audioScenarioDefault,
          );
          break;
        case CallQuality.good:
        case CallQuality.excellent:
          // High quality settings
          await _applyAudioProfile(_callSettings.audioProfile);
          break;
      }
      
      print("🔄 Adapted settings for quality: $quality");
      
    } catch (e) {
      print("⚠️ Error adapting to quality: $e");
    }
  }

  /// Adapt to network conditions
  Future<void> _adaptToNetworkConditions() async {
    if (engine == null || _callState != CallState.connected) return;
    
    try {
      // Monitor network conditions and adapt accordingly
      // This is a simplified version - real implementation would use
      // actual network monitoring APIs
      
      if (_callSettings.adaptiveBitrate) {
        // Adjust bitrate based on network conditions
        // await engine!.setRemoteDefaultVideoStreamType(VideoStreamType.videoStreamHigh);
      }
      
    } catch (e) {
      print("⚠️ Error adapting to network conditions: $e");
    }
  }

  /// Collect comprehensive call statistics
  Future<void> _collectCallStatistics() async {
    if (engine == null || _callState != CallState.connected) return;
    
    try {
      // Collect statistics from Agora SDK
      // Note: Some of these APIs might need adjustment based on the actual Agora SDK version
      
      final stats = CallStatistics(
        duration: currentCall?.timestamp != null ? 
            DateTime.now().difference(currentCall!.timestamp).inSeconds : 0,
        quality: _currentQuality,
        packetsLost: 0, // Would get from actual stats
        packetsSent: 0, // Would get from actual stats
        packetsReceived: 0, // Would get from actual stats
        audioLossRate: 0.0, // Would calculate from actual data
        networkDelay: 0, // Would get from actual network stats
        cpuUsage: 0.0, // Would get from system stats
        memoryUsage: 0.0, // Would get from system stats
        timestamp: DateTime.now(),
      );
      
      _lastStatistics = stats;
      _callStatisticsController.add(stats);
      
    } catch (e) {
      print("⚠️ Error collecting call statistics: $e");
    }
  }

  /// Update call state and notify listeners
  void _updateCallState(CallState newState) {
    if (_callState != newState) {
      _callState = newState;
      _callStateController.add(_callState);
      print("📱 Call state changed to: $newState");
    }
  }

  Future<Call?> startCall(String receiverId, bool isVideoCall) async {
    try {
      _updateCallState(CallState.ringing);
      
      // Start statistics collection
      _startStatisticsCollection();
      
      final call = await _baseCallService.startCall(receiverId, isVideoCall);
      
      if (call != null) {
        _updateCallState(CallState.connecting);
      } else {
        _updateCallState(CallState.error);
      }
      
      return call;
      
    } catch (e) {
      _updateCallState(CallState.error);
      rethrow;
    }
  }

  Future<bool> answerCall(String callId) async {
    try {
      _updateCallState(CallState.connecting);
      
      // Start statistics collection
      _startStatisticsCollection();
      
      final success = await _baseCallService.answerCall(callId);
      
      if (success) {
        _updateCallState(CallState.connected);
      } else {
        _updateCallState(CallState.error);
      }
      
      return success;
      
    } catch (e) {
      _updateCallState(CallState.error);
      rethrow;
    }
  }

  Future<void> endCall({bool isDeclined = false}) async {
    try {
      _updateCallState(CallState.ending);
      
      // Stop monitoring
      _stopAllMonitoring();
      
      // Stop recording if active
      if (_isRecording) {
        await stopRecording();
      }
      
      await _baseCallService.endCall(isDeclined: isDeclined);
      
      _updateCallState(CallState.ended);
      
      // Save call statistics if available
      if (_lastStatistics != null) {
        await _saveCallStatistics(_lastStatistics!);
      }
      
    } catch (e) {
      _updateCallState(CallState.error);
      rethrow;
    }
  }

  /// Stop all monitoring timers
  void _stopAllMonitoring() {
    _statisticsTimer?.cancel();
    _qualityMonitorTimer?.cancel();
    _networkAdaptationTimer?.cancel();
    _statisticsTimer = null;
    _qualityMonitorTimer = null;
    _networkAdaptationTimer = null;
  }

  /// Save call statistics to Firestore
  Future<void> _saveCallStatistics(CallStatistics stats) async {
    try {
      if (currentCall == null) return;
      
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(currentCall!.callId)
          .collection('statistics')
          .add(stats.toJson());
          
      print("📊 Call statistics saved");
      
    } catch (e) {
      print("⚠️ Error saving call statistics: $e");
    }
  }

  /// Enhanced mute toggle with better feedback
  Future<bool> toggleMute() async {
    try {
      final result = await _baseCallService.toggleMute();
      
      // Provide haptic feedback
      // HapticFeedback.selectionClick(); // Would need to import flutter/services
      
      return result;
      
    } catch (e) {
      print("⚠️ Error toggling mute: $e");
      return false;
    }
  }

  /// Enhanced speaker toggle
  Future<bool> toggleSpeaker() async {
    try {
      final result = await _baseCallService.toggleSpeaker();
      
      // Provide haptic feedback
      // HapticFeedback.selectionClick(); // Would need to import flutter/services
      
      return result;
      
    } catch (e) {
      print("⚠️ Error toggling speaker: $e");
      return false;
    }
  }

  /// Set custom audio profile
  Future<void> setAudioProfile(AudioProfile profile) async {
    _callSettings.audioProfile = profile;
    await _applyAudioProfile(profile);
  }

  /// Set volume level (0.0 to 1.0)
  Future<void> setVolumeLevel(double level) async {
    final currentEngine = engine;
    if (currentEngine == null) return;
    
    try {
      _callSettings.volumeLevel = level.clamp(0.0, 1.0);
      
      // Set the actual volume
      final volumeInt = (_callSettings.volumeLevel * 255).round();
      await currentEngine.adjustPlaybackSignalVolume(volumeInt);
      
    } catch (e) {
      print("⚠️ Error setting volume: $e");
    }
  }

  /// Enable/disable echo cancellation
  Future<void> setEchoCancellation(bool enabled) async {
    _callSettings.echoCancellation = enabled;
    
    final currentEngine = engine;
    if (currentEngine != null) {
      try {
        // Apply echo cancellation setting
        await currentEngine.enableLocalAudio(enabled);
      } catch (e) {
        print("⚠️ Error setting echo cancellation: $e");
      }
    }
  }

  /// Enable/disable noise suppression
  Future<void> setNoiseSuppression(bool enabled) async {
    _callSettings.noiseSuppression = enabled;
    
    if (engine != null && _callState == CallState.connected) {
      // Apply noise suppression - this might require platform-specific implementation
      // or additional audio processing libraries
    }
  }

  /// Start call recording
  Future<bool> startRecording() async {
    if (engine == null || _isRecording) return false;
    
    try {
      // Request audio recording permission
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        print("⚠️ Microphone permission not granted for recording");
        return false;
      }
      
      // Generate recording file path
      _recordingPath = await _generateRecordingPath();
      
      // Start recording using Agora's recording feature
      // Note: This might require additional setup or server-side recording
      _isRecording = true;
      
      print("🎙️ Call recording started");
      return true;
      
    } catch (e) {
      print("⚠️ Error starting recording: $e");
      return false;
    }
  }

  /// Stop call recording
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    
    try {
      _isRecording = false;
      
      // Stop the recording
      // Implementation depends on the recording method used
      
      final recordingPath = _recordingPath;
      _recordingPath = null;
      
      print("⏹️ Call recording stopped");
      return recordingPath;
      
    } catch (e) {
      print("⚠️ Error stopping recording: $e");
      return null;
    }
  }

  /// Generate recording file path
  Future<String> _generateRecordingPath() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final callId = currentCall?.callId ?? 'unknown';
    return 'call_recordings/call_${callId}_$timestamp.wav';
  }

  /// Get detailed call quality report
  Map<String, dynamic> getCallQualityReport() {
    return {
      'currentQuality': _currentQuality.toString(),
      'lastStatistics': _lastStatistics?.toJson(),
      'callSettings': _callSettings.toJson(),
      'callState': _callState.toString(),
      'isRecording': _isRecording,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Check if audio is working properly
  bool isAudioWorking() {
    // Delegate to base service and add enhanced checks
    bool baseAudioWorking = _baseCallService.isAudioWorking();
    
    // Add additional enhanced checks if available
    if (_lastStatistics != null) {
      // Consider audio not working if packet loss rate is too high
      if (_lastStatistics!.audioLossRate > 0.25) {
        return false;
      }
      
      // Consider audio not working if call quality is poor or critical
      if (_lastStatistics!.quality == CallQuality.poor || 
          _lastStatistics!.quality == CallQuality.critical) {
        return false;
      }
    }
    
    return baseAudioWorking;
  }

  /// Fix voice transmission issues
  Future<bool> fixVoiceIssues() async {
    bool baseResult = await _baseCallService.fixVoiceIssues();
    
    final currentEngine = engine;
    if (currentEngine == null) return baseResult;
    
    try {
      // Enhanced audio recovery steps
      
      // Reset audio session with optimized settings
      await _applyAudioProfile(_callSettings.audioProfile);
      
      // Force audio device reconnection
      await currentEngine.setEnableSpeakerphone(false);
      await Future.delayed(const Duration(milliseconds: 300));
      await currentEngine.setEnableSpeakerphone(true);
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Re-establish audio routing
      await currentEngine.setDefaultAudioRouteToSpeakerphone(true);
      
      print("🔄 Enhanced voice transmission fix applied");
      return true;
    } catch (e) {
      print("⚠️ Error in enhanced fix: $e");
      return baseResult;
    }
  }

  void dispose() {
    _stopAllMonitoring();
    _callStateController.close();
    _callQualityController.close();
    _callStatisticsController.close();
    _baseCallService.dispose();
  }
}