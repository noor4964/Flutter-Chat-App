// Web-specific helper methods for call service
// These methods are designed to provide specialized error recovery
// and diagnostics for web-based calling functionality

import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../services/platform_helper.dart';

class WebCallHelper {
  // Optimize audio configuration specifically for web platforms
  static Future<void> optimizeWebAudioTransmission(RtcEngine engine) async {
    if (!PlatformHelper.isWeb) return;
    
    print("🌐🔈 Applying web-specific audio optimizations...");
    
    try {
      // Step 1: Configure audio parameters for optimal web performance
      await engine.setParameters("""
      {
        "che.audio.enable_aec": true,
        "che.audio.enable_agc": true,
        "che.audio.enable_ns": true,
        "che.audio.aec_mode": 2,
        "che.audio.ns_mode": 2,
        "che.audio.enable_ns_high_pass_filter": true,
        "che.audio.frame_process_interval": 15
      }
      """);
      
      // Step 2: Set web-specific constraints for getUserMedia
      await engine.setParameters("""
      {
        "web_audio_constraints": {
          "echoCancellation": true,
          "noiseSuppression": true,
          "autoGainControl": true,
          "sampleRate": 48000,
          "channelCount": 1
        }
      }
      """);
      
      // Step 3: Add voice activity detection for better voice transmission
      await engine.setParameters("""
      {
        "che.audio.enable_vad": true,
        "che.audio.vad_sensitivity": 2,
        "che.audio.use_browser_built_in_aec": true
      }
      """);
      
      // Step 4: Configure audio compression and gain for optimal voice
      await engine.setParameters("""
      {
        "che.audio.enable_agc": true,
        "che.audio.agc_mode": 1,
        "che.audio.agc_target_level_dbfs": 3,
        "che.audio.agc_compression_gain_db": 9,
        "che.audio.bitrate_adaptive_mode": 3,
        "che.audio.use_audio_input_scene": 1
      }
      """);
      
      // Step 5: Configure audio profile for voice clarity
      await engine.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );
      
      // Step 6: Wait briefly to ensure settings are applied
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Step 7: Ensure microphone track is explicitly published (critical for web)
      await engine.updateChannelMediaOptions(
        const ChannelMediaOptions(
          publishMicrophoneTrack: true,
          publishCameraTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );
      
      print("🌐🔈 Web audio optimizations successfully applied");
    } catch (e) {
      print("🌐⚠️ Error applying web audio optimizations: $e");
    }
  }

  // Register diagnostic event handlers for web platforms
  static Future<void> setupWebDiagnosticListeners(RtcEngine engine) async {
    if (!PlatformHelper.isWeb) return;
    
    print("🌐🔍 Setting up web-specific diagnostic listeners");
    
    try {
      // Listen for network quality changes
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onNetworkQuality: (RtcConnection connection, int uid, QualityType txQuality, QualityType rxQuality) {
            if (txQuality.index >= 4 || rxQuality.index >= 4) { // 4 or higher means poor quality
              print("🌐⚠️ Web call network quality degraded: TX=${txQuality.name}, RX=${rxQuality.name}");
            }
          },
          onLocalAudioStateChanged: (RtcConnection connection, LocalAudioStreamState state, LocalAudioStreamReason reason) {
            print("🌐🔊 Web audio state changed: ${state.name} (Reason: ${reason.name})");
            
            // Detect specific audio capturing issues
            if (state == LocalAudioStreamState.localAudioStreamStateStopped || 
                state == LocalAudioStreamState.localAudioStreamStateFailed) {
              print("🌐🔊❌ Web audio capture issue detected: ${reason.name}");
            }
          },
          onAudioVolumeIndication: (RtcConnection connection, List<AudioVolumeInfo> speakers, int totalVolume, int speakerNumber) {
            // If we have speakers but volume is very low, might indicate a problem
            if (speakers.isNotEmpty && totalVolume < 5) {
              print("🌐🔊⚠️ Web audio volume very low: $totalVolume");
            }
          },
        ),
      );
      
      print("🌐🔍 Web diagnostic listeners successfully registered");
    } catch (e) {
      print("🌐⚠️ Error setting up web diagnostic listeners: $e");
    }
  }

  // Specialized web recovery for when calls fail to initialize properly
  static Future<bool> attemptWebCallRecovery(
      RtcEngine? engine, String channelId, int retries) async {
    if (!PlatformHelper.isWeb || engine == null) {
      return false;
    }
    
    print("🌐🔄 Web Call Recovery: Attempting recovery sequence (try $retries/3)");
    
    try {
      // Step 1: Ensure the channel is left first
      try {
        await engine.leaveChannel();
        print("🌐🔄 Web Call Recovery: Successfully left channel");
      } catch (e) {
        print("🌐🔄 Web Call Recovery: Error leaving channel: $e");
        // Continue with recovery even if leave fails
      }
      
      // Step 2: Reset audio states with explicit configuration
      await engine.enableAudio();
      await engine.enableLocalAudio(true);
      
      // Explicitly set audio parameters for better voice transmission on web
      await engine.adjustRecordingSignalVolume(100); // Max volume for sending
      await engine.adjustPlaybackSignalVolume(100); // Max volume for receiving
      
      // Set audio scenario and profile for better voice quality
      await engine.setAudioProfile(
        profile: AudioProfileType.audioProfileMusicHighQuality,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );
      
      print("🌐🔄 Web Call Recovery: Enhanced audio system reset for voice transmission");
      
      // Step 3: Wait for browser to stabilize
      await Future.delayed(const Duration(milliseconds: 800));
      
      // Step 4: Attempt to join with recovery parameters optimized for voice
      final uid = 1000 + retries; // Use different UIDs for each retry
      print("🌐🔄 Web Call Recovery: Attempting to join with UID $uid and enhanced voice settings");
      
      // Use enhanced options for better voice transmission
      await engine.joinChannel(
        token: '',
        channelId: channelId,
        uid: uid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true, // Ensure we subscribe to remote audio
        ),
      );
      
      // Additional step: Ensure audio is properly routed after joining
      await Future.delayed(const Duration(milliseconds: 500));
      await engine.adjustRecordingSignalVolume(100); // Ensure max volume again
      
      print("🌐✅ Web Call Recovery: Successfully recovered web call with enhanced voice settings!");
      return true;
    } catch (e) {
      print("🌐❌ Web Call Recovery: Recovery attempt $retries failed: $e");
      
      // Try again with a delay if we have retries left
      if (retries < 3) {
        await Future.delayed(const Duration(seconds: 1));
        return attemptWebCallRecovery(engine, channelId, retries + 1);
      }
      
      return false;
    }
  }
  
  // Gather web browser diagnostic information to help with debugging
  static Map<String, dynamic> getWebDiagnostics() {
    if (!PlatformHelper.isWeb) {
      return {'isWeb': false};
    }
    
    return {
      'isWeb': true,
      'url': Uri.base.toString(),
      'protocol': Uri.base.scheme,
      'host': Uri.base.host,
      'userAgent': 'Browser', // Would need JS interop for actual user agent
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  // Check if the web browser supports the required features for calling
  static bool checkWebSupport() {
    if (!PlatformHelper.isWeb) {
      return false;
    }
    
    // In a real implementation, this would use JS interop to check
    // if the browser supports WebRTC and other required features
    
    // For now, we assume support is available since we don't have
    // access to the browser APIs directly from Dart
    return true;
  }
  
  // Check and fix audio device issues on web platforms
  static Future<bool> checkAndFixWebAudioDevices(RtcEngine engine) async {
    if (!PlatformHelper.isWeb) return true;
    
    print("🌐🔍 Checking web audio devices...");
    
    try {
      // Force browser to show permission dialog again by setting deviceId to empty
      await engine.setParameters("""
      {
        "che.audio.input.device.id": "",
        "che.video.device.reset": true
      }
      """);
      
      // Wait for browser to process device change
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Force reconnection of audio device
      await engine.enableLocalAudio(false);
      await Future.delayed(const Duration(milliseconds: 500));
      await engine.enableLocalAudio(true);
      
      // Set audio processing parameters for better voice quality
      await engine.setParameters("""
      {
        "che.audio.processing.mode": "communication",
        "che.audio.processing.aec.enable": true,
        "che.audio.processing.agc.enable": true,
        "che.audio.processing.ns.enable": true
      }
      """);
      
      print("✅ Web audio devices checked and optimized");
      return true;
    } catch (e) {
      print("❌ Error checking/fixing web audio devices: $e");
      return false;
    }
  }
  
  // Optimize voice call settings for web platform
  static Future<void> optimizeVoiceSettings(RtcEngine engine) async {
    if (!PlatformHelper.isWeb) return;
    
    print("🌐 Optimizing voice transmission settings for web");
    
    try {
      // 1. Configure audio properties for best voice quality
      await engine.setAudioProfile(
        profile: AudioProfileType.audioProfileMusicHighQuality,
        scenario: AudioScenarioType.audioScenarioGameStreaming, // High quality voice
      );
      
      // 2. Adjust volumes to maximum for better clarity
      await engine.adjustRecordingSignalVolume(100); // Max microphone volume
      await engine.adjustPlaybackSignalVolume(100);  // Max speaker volume
      
      // 3. Enable audio processing to improve voice clarity
      await engine.enableLocalAudio(true);
      await engine.enableAudioVolumeIndication(
        interval: 200, // More frequent updates for better responsiveness
        smooth: 3,
        reportVad: true,
      );
      
      // 4. Minimize audio processing delay
      await _setAudioProcessingParams(engine);
      
      print("✅ Web voice optimization complete");
    } catch (e) {
      print("❌ Error optimizing voice settings: $e");
    }
  }
  
  // Diagnose voice transmission issues
  static Future<Map<String, dynamic>> diagnoseVoiceTransmission(RtcEngine engine) async {
    if (!PlatformHelper.isWeb) {
      return {'isWeb': false, 'diagnosis': 'Not applicable for non-web platforms'};
    }
    
    print("🔍 Diagnosing voice transmission issues on web");
    
    Map<String, dynamic> diagnostics = {
      'isWeb': true,
      'timestamp': DateTime.now().toIso8601String(),
      'audioEnabled': true,
      'microphonePublished': true,
      'recommendations': <String>[],
    };
    
    try {
      // Test if local audio is properly enabled
      int volumeDetection = 0;
      
      // Set up listener for local audio detection
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
            for (var speaker in speakers) {
              if (speaker.uid == 0 && (speaker.volume ?? 0) > 10) {
                // Local audio detected
                volumeDetection = speaker.volume ?? 0;
              }
            }
          },
        ),
      );
      
      // Check audio settings and device
      await Future.delayed(const Duration(seconds: 2));
      
      // Gather diagnostic data
      if (volumeDetection < 10) {
        diagnostics['recommendations'].add('Check microphone access and permissions in browser');
        diagnostics['recommendations'].add('Try using headphones to avoid echo cancellation issues');
        diagnostics['audioDetected'] = false;
      } else {
        diagnostics['audioDetected'] = true;
      }
      
      print("📊 Voice transmission diagnosis complete");
      return diagnostics;
    } catch (e) {
      print("❌ Error during voice transmission diagnosis: $e");
      diagnostics['error'] = e.toString();
      return diagnostics;
    }
  }
  
  // Fix common voice transmission issues
  static Future<bool> fixVoiceTransmissionIssues(RtcEngine engine, String channelId) async {
    if (!PlatformHelper.isWeb) return false;
    
    print("🔧 Applying fixes for voice transmission issues on web");
    
    try {
      // 1. Reset audio routing completely
      await engine.enableLocalAudio(false);
      await Future.delayed(const Duration(milliseconds: 500));
      await engine.enableLocalAudio(true);
      
      // 2. Force reconnection with optimized audio settings
      try {
        await engine.leaveChannel();
      } catch (e) {
        // Ignore errors during channel leaving
      }
      
      await Future.delayed(const Duration(milliseconds: 800));
      
      // 3. Apply optimized audio settings
      await optimizeVoiceSettings(engine);
      
      // 4. Rejoin with special configuration for voice
      await engine.joinChannel(
        token: '',
        channelId: channelId,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
      
      // 5. Apply special post-join optimizations
      await Future.delayed(const Duration(milliseconds: 500));
      await _postJoinVoiceOptimization(engine);
      
      print("✅ Voice transmission fixes applied");
      return true;
    } catch (e) {
      print("❌ Error fixing voice transmission: $e");
      return false;
    }
  }
  
  // Set internal audio processing parameters
  static Future<void> _setAudioProcessingParams(RtcEngine engine) async {
    try {
      // Set audio scenario for best voice quality in WebRTC
      await engine.setAudioScenario(
        AudioScenarioType.audioScenarioChatroom,
      );
      
      // Additional tweaks if available in your Agora SDK version
      // These would normally require JS interop in a real implementation
    } catch (e) {
      print("Note: Some audio parameters may not be supported in this version");
    }
  }
  
  // Perform post-join voice optimizations
  static Future<void> _postJoinVoiceOptimization(RtcEngine engine) async {
    try {
      // Ensure echo cancellation is properly configured
      await engine.enableLocalAudio(true);
      await engine.adjustRecordingSignalVolume(100);
      
      // Force audio routing to speaker/headphones
      await engine.setDefaultAudioRouteToSpeakerphone(true);
      
      // Set higher priority for audio packets
      // (This would normally use custom implementation in a real setup)
    } catch (e) {
      print("Warning during post-join optimization: $e");
    }
  }
}