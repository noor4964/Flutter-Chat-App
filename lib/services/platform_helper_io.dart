// Platform helper for non-web platforms (iOS, Android, Windows, macOS, Linux)
import 'dart:io' show Platform;

// This class provides platform detection functionality for non-web platforms
class PlatformHelperImpl {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  static bool get isWindows => Platform.isWindows;
}
