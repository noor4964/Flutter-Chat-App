import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;

class PlatformHelper {
  static bool get isDesktop {
    return kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  static bool get isMobile {
    return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  }

  static bool get isWeb => kIsWeb;

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  // Return appropriate padding based on platform
  static EdgeInsets getScreenPadding(BuildContext context) {
    if (isDesktop) {
      double width = MediaQuery.of(context).size.width;
      // For desktops, provide more padding on larger screens
      if (width > 1200) {
        return const EdgeInsets.symmetric(horizontal: 200.0, vertical: 20.0);
      } else if (width > 800) {
        return const EdgeInsets.symmetric(horizontal: 100.0, vertical: 16.0);
      } else {
        return const EdgeInsets.symmetric(horizontal: 40.0, vertical: 12.0);
      }
    } else {
      // Mobile padding
      return const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
    }
  }

  // Get appropriate layout for chat based on platform
  static double getChatListWidth(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    if (isDesktop) {
      return screenWidth * 0.3; // 30% of screen width for desktop
    } else {
      return screenWidth; // Full width for mobile
    }
  }

  // Get appropriate font size multiplier based on platform
  static double getFontSizeMultiplier() {
    if (isDesktop) {
      return 1.2; // Slightly larger font for desktop
    } else {
      return 1.0; // Standard font for mobile
    }
  }

  // Check if camera is available on this platform
  static bool isCameraAvailable() {
    return !isDesktop || kIsWeb; // Camera not available on desktop except web
  }
}
