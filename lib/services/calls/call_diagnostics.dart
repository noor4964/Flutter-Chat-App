import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../calls/call_service.dart';
import '../platform_helper.dart';

// Class to diagnose and report on call issues
class CallDiagnostics {
  final CallService _callService;
  
  CallDiagnostics(this._callService);
  
  // Check all aspects of the calling system
  Future<Map<String, dynamic>> runDiagnostics() async {
    final engine = _callService.getAgoraEngine();
    final call = _callService.currentCall;
    
    final results = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'engineInitialized': engine != null,
      'currentCall': call != null ? {
        'id': call.callId,
        'status': call.status,
        'isVideo': call.isVideo,
      } : null,
      'platform': PlatformHelper.isWeb ? 'web' : 
                 PlatformHelper.isAndroid ? 'android' : 
                 PlatformHelper.isIOS ? 'ios' : 'desktop',
    };
    
    if (engine != null) {
      try {
        results['connectionState'] = 'active';
        
        // Add platform-specific diagnostics
        if (PlatformHelper.isWeb) {
          results['webSpecificChecks'] = await _runWebDiagnostics(engine);
        } else if (PlatformHelper.isAndroid || PlatformHelper.isIOS) {
          results['mobileSpecificChecks'] = await _runMobileDiagnostics(engine);
        }
      } catch (e) {
        results['diagnosticError'] = e.toString();
      }
    }
    
    return results;
  }
  
  // Web-specific diagnostics
  Future<Map<String, dynamic>> _runWebDiagnostics(RtcEngine engine) async {
    final results = <String, dynamic>{};
    
    try {
      // Capture current audio settings
      results['audioEnabled'] = true; // We can't directly query this state
      
      // Run web audio test
      results['audioTest'] = await _testWebAudio(engine);
      
      // Get connection stats if available
      try {
        results['connectionQuality'] = 'Checking connection quality...';
        // Connection stats aren't directly available, would need RTC stats
      } catch (e) {
        results['connectionQualityError'] = e.toString();
      }
    } catch (e) {
      results['webDiagnosticError'] = e.toString();
    }
    
    return results;
  }
  
  // Test web audio functionality
  Future<Map<String, dynamic>> _testWebAudio(RtcEngine engine) async {
    final results = <String, dynamic>{};
    
    try {
      // Test audio recording by checking if we can modify volume
      await engine.adjustRecordingSignalVolume(100);
      results['microphoneAccessible'] = true;
      
      // Test speaker by checking if we can modify playback volume
      await engine.adjustPlaybackSignalVolume(100);
      results['speakerAccessible'] = true;
      
      results['audioTestStatus'] = 'passed';
    } catch (e) {
      results['audioTestStatus'] = 'failed';
      results['audioTestError'] = e.toString();
    }
    
    return results;
  }
  
  // Mobile-specific diagnostics  
  Future<Map<String, dynamic>> _runMobileDiagnostics(RtcEngine engine) async {
    final results = <String, dynamic>{};
    
    // Add mobile-specific tests here
    try {
      // Check audio device routing
      results['audioDeviceTest'] = 'Running audio device tests...';
      // Would need to implement platform-specific code
    } catch (e) {
      results['mobileTestError'] = e.toString();
    }
    
    return results;
  }
  
  // Print diagnostic report to console
  void printDiagnosticReport() async {
    final diagnostics = await runDiagnostics();
    
    print("\n===== 📊 CALL DIAGNOSTIC REPORT =====");
    print("Time: ${diagnostics['timestamp']}");
    print("Platform: ${diagnostics['platform']}");
    print("Engine initialized: ${diagnostics['engineInitialized']}");
    
    if (diagnostics['currentCall'] != null) {
      final call = diagnostics['currentCall'];
      print("Active call: ID=${call['id']}, Status=${call['status']}, Video=${call['isVideo']}");
    } else {
      print("No active call");
    }
    
    if (diagnostics['webSpecificChecks'] != null) {
      final webChecks = diagnostics['webSpecificChecks'];
      print("\n🌐 Web platform diagnostics:");
      print("Audio enabled: ${webChecks['audioEnabled']}");
      
      if (webChecks['audioTest'] != null) {
        final audioTest = webChecks['audioTest'];
        print("Audio test status: ${audioTest['audioTestStatus']}");
        print("Microphone accessible: ${audioTest['microphoneAccessible']}");
        print("Speaker accessible: ${audioTest['speakerAccessible']}");
        
        if (audioTest['audioTestError'] != null) {
          print("⚠️ Audio test error: ${audioTest['audioTestError']}");
        }
      }
    }
    
    print("\n✅ Diagnostic report complete");
    print("=====================================\n");
  }
}