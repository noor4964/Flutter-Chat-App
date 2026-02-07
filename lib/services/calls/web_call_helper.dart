// Web-specific helper methods for call service
// Provides audio recovery for web-based calling

import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../services/platform_helper.dart';

class WebCallHelper {
  /// Check if the web browser supports calling features.
  /// Returns true on web (assumes WebRTC support in modern browsers).
  static bool checkWebSupport() {
    return PlatformHelper.isWeb;
  }

  /// Attempt to recover a failed web call by leaving and rejoining the channel.
  /// Makes a single recovery attempt (no recursive retries).
  static Future<bool> attemptWebCallRecovery(
      RtcEngine? engine, String channelId) async {
    if (!PlatformHelper.isWeb || engine == null) return false;

    print("Web Call Recovery: Attempting recovery...");

    try {
      // Leave the channel first
      try {
        await engine.leaveChannel();
      } catch (_) {
        // Continue even if leave fails
      }

      // Reset audio state
      await engine.enableAudio();
      await engine.enableLocalAudio(true);
      await engine.adjustRecordingSignalVolume(100);
      await engine.adjustPlaybackSignalVolume(100);

      await engine.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );

      // Wait for browser to stabilize
      await Future.delayed(const Duration(milliseconds: 800));

      // Rejoin with standard options
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

      // Ensure volume after rejoin
      await Future.delayed(const Duration(milliseconds: 500));
      await engine.adjustRecordingSignalVolume(100);

      print("Web Call Recovery: Successfully recovered");
      return true;
    } catch (e) {
      print("Web Call Recovery: Failed - $e");
      return false;
    }
  }
}
