import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_chat_app/services/settings_service.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  String _fontSize = 'Medium';
  bool _useAnimations = true;
  bool _useBlurEffects = true;
  double _borderRadius = 16.0;
  String _chatBubbleStyle = 'Modern';
  Color _primaryColor = Colors.deepPurple;
  late ThemeData _themeData;
  final SettingsService _settingsService = SettingsService();

  bool get isDarkMode => _isDarkMode;
  String get fontSize => _fontSize;
  bool get useAnimations => _useAnimations;
  bool get useBlurEffects => _useBlurEffects;
  double get borderRadius => _borderRadius;
  String get chatBubbleStyle => _chatBubbleStyle;
  Color get primaryColor => _primaryColor;
  ThemeData get themeData => _themeData;

  // Font size scaling factors
  final Map<String, double> _fontSizeFactors = {
    'Small': 0.8,
    'Medium': 1.0,
    'Large': 1.2,
    'Extra Large': 1.4,
  };

  ThemeProvider() {
    _themeData = _buildLightTheme();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    // Load theme preference
    _isDarkMode = await _settingsService.isDarkMode();

    // Load font size preference
    _fontSize = await _settingsService.getFontSize();

    // Load animation preference
    _useAnimations = await _settingsService.useAnimations();

    // Load blur effects preference
    _useBlurEffects = await _settingsService.useBlurEffects();

    // Load border radius
    _borderRadius = await _settingsService.getBorderRadius();

    // Load chat bubble style
    _chatBubbleStyle = await _settingsService.getChatBubbleStyle();

    // Load primary color
    int colorValue = await _settingsService.getPrimaryColor();
    _primaryColor = Color(colorValue);

    // Apply theme and font size
    _themeData = _isDarkMode ? _buildDarkTheme() : _buildLightTheme();

    notifyListeners();
  }

  void setTheme(bool isDarkMode) async {
    _isDarkMode = isDarkMode;
    _themeData = isDarkMode ? _buildDarkTheme() : _buildLightTheme();

    // Save preference
    await _settingsService.setDarkMode(isDarkMode);

    notifyListeners();
  }

  void setFontSize(String fontSize) async {
    if (_fontSizeFactors.containsKey(fontSize)) {
      _fontSize = fontSize;

      // Rebuild theme with new font size
      _themeData = _isDarkMode ? _buildDarkTheme() : _buildLightTheme();

      // Save preference
      await _settingsService.setFontSize(fontSize);

      notifyListeners();
    }
  }

  void setUseAnimations(bool useAnimations) async {
    _useAnimations = useAnimations;

    // Save preference
    await _settingsService.setUseAnimations(useAnimations);

    notifyListeners();
  }

  void setUseBlurEffects(bool useBlurEffects) async {
    _useBlurEffects = useBlurEffects;

    // Save preference
    await _settingsService.setUseBlurEffects(useBlurEffects);

    notifyListeners();
  }

  void setBorderRadius(double radius) async {
    _borderRadius = radius;

    // Rebuild theme with new border radius
    _themeData = _isDarkMode ? _buildDarkTheme() : _buildLightTheme();

    // Save preference
    await _settingsService.setBorderRadius(radius);

    notifyListeners();
  }

  void setChatBubbleStyle(String style) async {
    _chatBubbleStyle = style;

    // Save preference
    await _settingsService.setChatBubbleStyle(style);

    notifyListeners();
  }

  void setPrimaryColor(Color color) async {
    _primaryColor = color;

    // Rebuild theme with new color
    _themeData = _isDarkMode ? _buildDarkTheme() : _buildLightTheme();

    // Save preference
    await _settingsService.setPrimaryColor(color.value);

    notifyListeners();
  }

  // Get the current font size multiplier
  double get fontSizeMultiplier => _fontSizeFactors[_fontSize] ?? 1.0;

  ThemeData _buildLightTheme() {
    final ColorScheme colorScheme = ColorScheme.light(
      primary: _primaryColor,
      secondary: _primaryColor.withOpacity(0.7),
      surface: Colors.white,
      background: Colors.grey[50]!,
      error: Colors.red[700]!,
    );

    final baseTheme = ThemeData(
      colorScheme: colorScheme,
      brightness: Brightness.light,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: _useBlurEffects ? 2 : 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadius),
          ),
          elevation: _useBlurEffects ? 4 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      cardTheme: CardTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
        elevation: _useBlurEffects ? 4 : 1,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadius),
          ),
        ),
      ),
      iconTheme: IconThemeData(
        color: _primaryColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          borderSide: BorderSide(color: _primaryColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.grey[200],
        disabledColor: Colors.grey[300],
        selectedColor: _primaryColor.withOpacity(0.2),
        secondarySelectedColor: _primaryColor.withOpacity(0.2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius / 2),
        ),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: _primaryColor,
        unselectedLabelColor: Colors.grey[600],
        indicator: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _primaryColor,
              width: 2.0,
            ),
          ),
        ),
      ),
      useMaterial3: true,
    );

    return _applyFontSize(baseTheme);
  }

  ThemeData _buildDarkTheme() {
    final ColorScheme colorScheme = ColorScheme.dark(
      primary: _primaryColor,
      secondary: _primaryColor.withOpacity(0.7),
      surface: Colors.grey[900]!,
      background: Colors.grey[850]!,
      error: Colors.red[500]!,
    );

    final baseTheme = ThemeData(
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: _useBlurEffects ? 2 : 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadius),
          ),
          elevation: _useBlurEffects ? 4 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      cardTheme: CardTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
        elevation: _useBlurEffects ? 4 : 1,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        color: Colors.grey[850],
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadius),
          ),
        ),
      ),
      iconTheme: IconThemeData(
        color: _primaryColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          borderSide: BorderSide(color: _primaryColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[800],
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.grey[700],
        disabledColor: Colors.grey[600],
        selectedColor: _primaryColor.withOpacity(0.2),
        secondarySelectedColor: _primaryColor.withOpacity(0.2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius / 2),
        ),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: _primaryColor,
        unselectedLabelColor: Colors.grey[400],
        indicator: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _primaryColor,
              width: 2.0,
            ),
          ),
        ),
      ),
      useMaterial3: true,
    );

    return _applyFontSize(baseTheme);
  }

  // Apply font size scaling to a theme
  ThemeData _applyFontSize(ThemeData baseTheme) {
    return baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        fontSizeFactor: fontSizeMultiplier,
      ),
      primaryTextTheme: baseTheme.primaryTextTheme.apply(
        fontSizeFactor: fontSizeMultiplier,
      ),
    );
  }
}
