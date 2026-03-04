import 'package:shared_preferences/shared_preferences.dart';

/// A service that manages app-wide settings
class SettingsService {
  // Preference keys
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _soundEnabledKey = 'sound_enabled';
  static const String _fontSizeKey = 'font_size';
  static const String _chatBackupEnabledKey = 'chat_backup_enabled';
  static const String _languageKey = 'language';
  static const String _isDarkModeKey = 'is_dark_mode';
  static const String _themeStyleKey = 'theme_style'; // 'light', 'dark'
  static const String _liquidGlassEnabledKey = 'liquid_glass_enabled';
  static const String _glassPaletteKey = 'glass_palette';
  static const String _glassBlurSigmaKey = 'glass_blur_sigma';
  static const String _glassMeshSpeedKey = 'glass_mesh_speed';
  static const String _useAnimationsKey = 'use_animations';
  static const String _primaryColorKey = 'primary_color';
  static const String _borderRadiusKey = 'border_radius';
  static const String _bubbleStyleKey = 'chat_bubble_style';
  static const String _useBlurEffectsKey = 'use_blur_effects';
  static const String _appearOfflineKey = 'appear_offline';
  static const String _readReceiptsEnabledKey = 'read_receipts_enabled';
  static const String _showLastSeenKey = 'show_last_seen';
  static const String _enterSendsMessageKey = 'enter_sends_message';
  static const String _mediaAutoDownloadKey = 'media_auto_download';
  static const String _backupFrequencyKey = 'backup_frequency';

  // Singleton pattern
  static final SettingsService _instance = SettingsService._internal();

  factory SettingsService() {
    return _instance;
  }

  SettingsService._internal();

  // Font size values and conversions
  final Map<String, double> _fontSizeFactors = {
    'Small': 0.8,
    'Medium': 1.0,
    'Large': 1.2,
    'Extra Large': 1.4,
  };

  // Font size helpers
  Future<double> getFontSizeFactor() async {
    final fontSize = await getFontSize();
    return _fontSizeFactors[fontSize] ?? 1.0;
  }

  Future<double> scaleFontSize(double baseSize) async {
    final factor = await getFontSizeFactor();
    return baseSize * factor;
  }

  // Notification settings
  Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? false;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
  }

  // Sound settings
  Future<bool> isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundEnabledKey) ?? true;
  }

  Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, enabled);
  }

  // Font size settings
  Future<String> getFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fontSizeKey) ?? 'Medium';
  }

  Future<void> setFontSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontSizeKey, size);
  }

  // Chat backup settings
  Future<bool> isChatBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chatBackupEnabledKey) ?? false;
  }

  Future<void> setChatBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chatBackupEnabledKey, enabled);
  }

  // Language settings
  Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? 'English';
  }

  Future<void> setLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language);
  }

  // Theme settings
  Future<bool> isDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isDarkModeKey) ?? false;
  }

  Future<void> setDarkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isDarkModeKey, enabled);
  }

  // Theme style (light/dark/glass) - supersedes isDarkMode for new UI
  Future<String> getThemeStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final style = prefs.getString(_themeStyleKey);
    if (style != null) {
      return style;
    }
    // Fallback to legacy dark mode check
    final isDark = prefs.getBool(_isDarkModeKey) ?? false;
    return isDark ? 'dark' : 'light';
  }

  Future<void> setThemeStyle(String style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeStyleKey, style);
    // Keep legacy key in sync for backward compat
    await prefs.setBool(_isDarkModeKey, style == 'dark');
  }

  // Liquid glass toggle (independent of light/dark mode)
  Future<bool> isLiquidGlassEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_liquidGlassEnabledKey) ?? false;
  }

  Future<void> setLiquidGlassEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liquidGlassEnabledKey, enabled);
  }

  // Glass customization
  Future<String> getGlassPalette() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_glassPaletteKey) ?? 'ocean';
  }

  Future<void> setGlassPalette(String palette) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_glassPaletteKey, palette);
  }

  Future<double> getGlassBlurSigma() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_glassBlurSigmaKey) ?? 10.0;
  }

  Future<void> setGlassBlurSigma(double sigma) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_glassBlurSigmaKey, sigma);
  }

  Future<double> getGlassMeshSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_glassMeshSpeedKey) ?? 50.0;
  }

  Future<void> setGlassMeshSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_glassMeshSpeedKey, speed);
  }

  // UI Animation settings
  Future<bool> useAnimations() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useAnimationsKey) ?? true;
  }

  Future<void> setUseAnimations(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useAnimationsKey, enabled);
  }

  // Theme color settings
  Future<int> getPrimaryColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_primaryColorKey) ??
        0xFF673AB7; // Default to deep purple
  }

  Future<void> setPrimaryColor(int colorValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_primaryColorKey, colorValue);
  }

  // UI Border radius setting
  Future<double> getBorderRadius() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_borderRadiusKey) ?? 16.0;
  }

  Future<void> setBorderRadius(double radius) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_borderRadiusKey, radius);
  }

  // Chat bubble style
  Future<String> getChatBubbleStyle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_bubbleStyleKey) ?? 'Modern';
  }

  Future<void> setChatBubbleStyle(String style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bubbleStyleKey, style);
  }

  // Blur effects for modals and cards
  Future<bool> useBlurEffects() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useBlurEffectsKey) ?? true;
  }

  Future<void> setUseBlurEffects(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useBlurEffectsKey, enabled);
  }

  // Appear offline setting
  Future<bool> isAppearOffline() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_appearOfflineKey) ?? false;
  }

  Future<void> setAppearOffline(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appearOfflineKey, enabled);
  }

  // Read receipts setting
  Future<bool> isReadReceiptsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_readReceiptsEnabledKey) ?? true;
  }

  Future<void> setReadReceiptsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_readReceiptsEnabledKey, enabled);
  }

  // Show last seen setting
  Future<bool> isShowLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showLastSeenKey) ?? true;
  }

  Future<void> setShowLastSeen(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showLastSeenKey, enabled);
  }

  // Enter sends message setting
  Future<bool> isEnterSendsMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enterSendsMessageKey) ?? true;
  }

  Future<void> setEnterSendsMessage(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enterSendsMessageKey, enabled);
  }

  // Media auto-download setting ('always', 'wifi_only', 'never')
  Future<String> getMediaAutoDownload() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mediaAutoDownloadKey) ?? 'always';
  }

  Future<void> setMediaAutoDownload(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mediaAutoDownloadKey, mode);
  }

  // Backup frequency setting ('daily', 'weekly', 'monthly')
  Future<String> getBackupFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_backupFrequencyKey) ?? 'weekly';
  }

  Future<void> setBackupFrequency(String frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backupFrequencyKey, frequency);
  }

  /// Read all theme-related preferences synchronously from an already-loaded
  /// SharedPreferences instance. Called from main() before runApp() so the
  /// theme is available on the first frame without async gaps.
  static Map<String, dynamic> readThemePrefsSync(SharedPreferences prefs) {
    String themeStyle;
    final storedStyle = prefs.getString(_themeStyleKey);
    if (storedStyle != null) {
      themeStyle = storedStyle;
    } else {
      final isDark = prefs.getBool(_isDarkModeKey) ?? false;
      themeStyle = isDark ? 'dark' : 'light';
    }

    return {
      'themeStyle': themeStyle,
      'fontSize': prefs.getString(_fontSizeKey) ?? 'Medium',
      'useAnimations': prefs.getBool(_useAnimationsKey) ?? true,
      'useBlurEffects': prefs.getBool(_useBlurEffectsKey) ?? true,
      'borderRadius': prefs.getDouble(_borderRadiusKey) ?? 16.0,
      'chatBubbleStyle': prefs.getString(_bubbleStyleKey) ?? 'Modern',
      'primaryColor': prefs.getInt(_primaryColorKey) ?? 0xFF673AB7,
      'glassPalette': prefs.getString(_glassPaletteKey) ?? 'ocean',
      'glassBlurSigma':
          (prefs.getDouble(_glassBlurSigmaKey) ?? 10.0).clamp(0.0, 20.0),
      'glassMeshSpeed': prefs.getDouble(_glassMeshSpeedKey) ?? 50.0,
    };
  }

  // Reset all settings to defaults
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, false);
    await prefs.setBool(_soundEnabledKey, true);
    await prefs.setString(_fontSizeKey, 'Medium');
    await prefs.setBool(_chatBackupEnabledKey, false);
    await prefs.setString(_languageKey, 'English');
    await prefs.setBool(_isDarkModeKey, false);
    await prefs.setBool(_useAnimationsKey, true);
    await prefs.setInt(_primaryColorKey, 0xFF673AB7);
    await prefs.setDouble(_borderRadiusKey, 16.0);
    await prefs.setString(_bubbleStyleKey, 'Modern');
    await prefs.setBool(_useBlurEffectsKey, true);
    await prefs.setBool(_appearOfflineKey, false);
    await prefs.setBool(_readReceiptsEnabledKey, true);
    await prefs.setBool(_showLastSeenKey, true);
    await prefs.setBool(_enterSendsMessageKey, true);
    await prefs.setString(_mediaAutoDownloadKey, 'always');
    await prefs.setString(_backupFrequencyKey, 'weekly');
  }
}
