// Platform helper for web platform
// This implementation avoids dart:io which is not available on web

// This class provides platform detection stubs for web platform
class PlatformHelperImpl {
  // Web is considered a desktop platform
  static bool get isDesktop => true;

  // Web is not considered a mobile platform
  static bool get isMobile => false;

  // Web is not Windows
  static bool get isWindows => false;
}
