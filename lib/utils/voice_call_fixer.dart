import 'dart:async';
import '../services/calls/call_service.dart';
import '../services/platform_helper.dart';
import '../services/calls/web_call_helper.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// A utility class to fix common voice calling issues
class VoiceCallFixer {
  /// Check and fix voice transmission issues for ongoing calls
  static Future<bool> checkAndFixVoiceTransmission() async {
    // Get access to the call service singleton
    final callService = CallService();
    final currentCall = callService.currentCall;
    
    if (currentCall == null) {
      print("❌ No active call to fix");
      return false;
    }
    
    print("🔍 Checking voice transmission for call: ${currentCall.callId}");
    
    if (PlatformHelper.isWeb) {
      print("🌐 Detected web platform - applying web-specific voice fixes");
      return _fixWebVoiceTransmission(callService, currentCall.callId);
    } else if (PlatformHelper.isAndroid) {
      print("🤖 Detected Android platform - applying Android-specific voice fixes");
      return _fixAndroidVoiceTransmission(callService);
    } else {
      print("📱 Applying general voice fixes");
      return _fixGeneralVoiceTransmission(callService);
    }
  }
  
  /// Fix web-specific voice transmission issues
  static Future<bool> _fixWebVoiceTransmission(CallService service, String callId) async {
    try {
      // Get the engine from the service through its fixVoiceIssues method
      final fixed = await service.fixVoiceIssues();
      
      if (!fixed) {
        print("⚠️ Basic voice fix unsuccessful, attempting deep fix");
        
        // Use our specialized WebCallHelper
        final engine = service.getAgoraEngine();
        if (engine != null) {
          return WebCallHelper.fixVoiceTransmissionIssues(engine, callId);
        }
      }
      
      return fixed;
    } catch (e) {
      print("❌ Error fixing web voice transmission: $e");
      return false;
    }
  }
  
  /// Fix Android-specific voice transmission issues
  static Future<bool> _fixAndroidVoiceTransmission(CallService service) async {
    try {
      // First try the standard fix
      final fixed = await service.fixVoiceIssues();
      
      if (!fixed) {
        // Apply Android-specific audio routing fixes
        final engine = service.getAgoraEngine();
        if (engine != null) {
          await engine.setDefaultAudioRouteToSpeakerphone(true);
          await engine.adjustRecordingSignalVolume(100);
          await engine.adjustPlaybackSignalVolume(100);
          
          // Force audio routing to speaker
          await engine.setEnableSpeakerphone(true);
          
          print("🤖 Applied Android-specific voice fixes");
          return true;
        }
      }
      
      return fixed;
    } catch (e) {
      print("❌ Error fixing Android voice transmission: $e");
      return false;
    }
  }
  
  /// Fix general voice transmission issues
  static Future<bool> _fixGeneralVoiceTransmission(CallService service) async {
    try {
      return await service.fixVoiceIssues();
    } catch (e) {
      print("❌ Error fixing voice transmission: $e");
      return false;
    }
  }
}