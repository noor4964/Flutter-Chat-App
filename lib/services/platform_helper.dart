import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'platform_helper_io.dart'
    if (dart.library.html) 'platform_helper_web.dart';
import 'package:flutter_chat_app/services/settings_service.dart';

class PlatformHelper {
  static final SettingsService _settingsService = SettingsService();

  // These getters delegate to the platform-specific implementations
  static bool get isDesktop => kIsWeb || PlatformHelperImpl.isDesktop;
  static bool get isMobile => !kIsWeb && PlatformHelperImpl.isMobile;
  static bool get isWeb => kIsWeb;
  static bool get isWindows => !kIsWeb && PlatformHelperImpl.isWindows;

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

  // Get appropriate font size multiplier based on platform and settings
  static Future<double> getFontSizeMultiplier() async {
    double platformMultiplier = isDesktop ? 1.2 : 1.0;

    // Get user's font size preference
    String fontSizePreference = await _settingsService.getFontSize();

    // Apply font size preference multiplier
    double settingsMultiplier = 1.0;
    switch (fontSizePreference) {
      case 'Small':
        settingsMultiplier = 0.8;
        break;
      case 'Medium':
        settingsMultiplier = 1.0;
        break;
      case 'Large':
        settingsMultiplier = 1.2;
        break;
    }

    return platformMultiplier * settingsMultiplier;
  }

  // Adjust text size based on platform and user settings
  static Future<double> getAdjustedTextSize(double baseSize) async {
    double multiplier = await getFontSizeMultiplier();
    return baseSize * multiplier;
  }

  // Check if camera is available on this platform
  static bool isCameraAvailable() {
    return !isDesktop || kIsWeb; // Camera not available on desktop except web
  }
}
