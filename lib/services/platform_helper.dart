import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Helper class to detect platform types
class PlatformHelper {
  /// Check if the current platform is a desktop (Windows, macOS, or Linux)
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// Check if the current platform is mobile (Android or iOS)
  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Check if the current platform is Windows
  static bool get isWindows {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  /// Check if the current platform is macOS
  static bool get isMacOS {
    if (kIsWeb) return false;
    return Platform.isMacOS;
  }

  /// Check if the current platform is Linux
  static bool get isLinux {
    if (kIsWeb) return false;
    return Platform.isLinux;
  }

  /// Check if the current platform is Android
  static bool get isAndroid {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// Check if the current platform is iOS
  static bool get isIOS {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  /// Check if the current platform is Web
  static bool get isWeb => kIsWeb;

  /// Get the width for chat list based on screen size and platform
  static double getChatListWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (isDesktop) {
      // On larger screens, use 30% of the width with a minimum of 300
      return screenWidth < 1200
          ? math.max(300, screenWidth * 0.3)
          : math.max(350, screenWidth * 0.25);
    } else {
      // On mobile, use full width
      return screenWidth;
    }
  }

  /// Check if camera is available on this platform
  static bool isCameraAvailable() {
    // Camera is not available on web or desktop (unless specifically implemented)
    if (isWeb) return false;

    // For now, assume camera is available on mobile platforms
    return isAndroid || isIOS;
  }
}
