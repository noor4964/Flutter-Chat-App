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
  static const String _useAnimationsKey = 'use_animations';
  static const String _primaryColorKey = 'primary_color';
  static const String _borderRadiusKey = 'border_radius';
  static const String _bubbleStyleKey = 'chat_bubble_style';
  static const String _useBlurEffectsKey = 'use_blur_effects';

  // Singleton pattern
  static final SettingsService _instance = SettingsService._internal();

  factory SettingsService() {
    return _instance;
  }

  SettingsService._internal();

  // Font size values and conversions
  Map<String, double> _fontSizeFactors = {
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
  }
}
