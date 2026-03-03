import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/settings_service.dart';

/// Theme style options
enum ThemeStyle { light, dark, glass }

class ThemeProvider extends ChangeNotifier {
  ThemeStyle _themeStyle = ThemeStyle.light;
  String _fontSize = 'Medium';
  bool _useAnimations = true;
  bool _useBlurEffects = true;
  double _borderRadius = 16.0;
  String _chatBubbleStyle = 'Modern';
  Color _primaryColor = Colors.deepPurple;
  
  // Glass theme customization
  String _glassPalette = 'ocean';
  double _glassBlurSigma = 10.0;
  double _glassMeshSpeed = 50.0;

  late ThemeData _themeData;
  final SettingsService _settingsService = SettingsService();
  Timer? _sliderDebounce;

  // Getters
  ThemeStyle get themeStyle => _themeStyle;
  bool get isDarkMode => _themeStyle == ThemeStyle.dark;
  bool get isGlassMode => _themeStyle == ThemeStyle.glass;
  String get fontSize => _fontSize;
  bool get useAnimations => _useAnimations;
  bool get useBlurEffects => _useBlurEffects || isGlassMode; // Always true for glass
  double get borderRadius => _borderRadius;
  String get chatBubbleStyle => _chatBubbleStyle;
  Color get primaryColor => _primaryColor;
  ThemeData get themeData => _themeData;
  
  // Glass getters
  String get glassPalette => _glassPalette;
  double get glassBlurSigma => _glassBlurSigma;
  double get glassMeshSpeed => _glassMeshSpeed;

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
    // Load theme style (replaces isDarkMode)
    final styleStr = await _settingsService.getThemeStyle();
    _themeStyle = ThemeStyle.values.firstWhere(
      (s) => s.name == styleStr,
      orElse: () => ThemeStyle.light,
    );

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

    // Load glass customization
    _glassPalette = await _settingsService.getGlassPalette();
    _glassBlurSigma = (await _settingsService.getGlassBlurSigma()).clamp(0, 20);
    _glassMeshSpeed = await _settingsService.getGlassMeshSpeed();

    // Apply theme
    _rebuildTheme();
    notifyListeners();
  }

  void _rebuildTheme() {
    switch (_themeStyle) {
      case ThemeStyle.light:
        _themeData = _buildLightTheme();
        break;
      case ThemeStyle.dark:
        _themeData = _buildDarkTheme();
        break;
      case ThemeStyle.glass:
        _themeData = _buildGlassTheme();
        break;
    }
  }

  /// Set theme style (light/dark/glass)
  void setThemeStyle(ThemeStyle style) async {
    _themeStyle = style;
    _rebuildTheme();
    await _settingsService.setThemeStyle(style.name);
    notifyListeners();
  }

  /// Toggle liquid glass on/off from the appearance settings switch.
  void setLiquidGlass(bool enabled) {
    if (enabled) {
      setThemeStyle(ThemeStyle.glass);
    } else {
      setThemeStyle(ThemeStyle.light);
    }
  }

  /// Legacy method for backward compatibility
  void setTheme(bool isDarkMode) async {
    setThemeStyle(isDarkMode ? ThemeStyle.dark : ThemeStyle.light);

    // Save preference
    await _settingsService.setDarkMode(isDarkMode);

    notifyListeners();
  }

  void setFontSize(String fontSize) async {
    if (_fontSizeFactors.containsKey(fontSize)) {
      _fontSize = fontSize;

      // Rebuild theme with new font size
      _rebuildTheme();

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

  void setBorderRadius(double radius) {
    _borderRadius = radius;
    _sliderDebounce?.cancel();
    _sliderDebounce = Timer(const Duration(milliseconds: 100), () {
      _rebuildTheme();
      _settingsService.setBorderRadius(radius);
      notifyListeners();
    });
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
    _rebuildTheme();

    // Save preference
    await _settingsService.setPrimaryColor(color.value);

    notifyListeners();
  }

  // Glass customization setters
  void setGlassPalette(String palette) async {
    _glassPalette = palette;
    await _settingsService.setGlassPalette(palette);
    notifyListeners();
  }

  void setGlassBlurSigma(double sigma) {
    _glassBlurSigma = sigma;
    _sliderDebounce?.cancel();
    _sliderDebounce = Timer(const Duration(milliseconds: 100), () {
      _settingsService.setGlassBlurSigma(sigma);
      notifyListeners();
    });
  }

  void setGlassMeshSpeed(double speed) {
    _glassMeshSpeed = speed;
    _sliderDebounce?.cancel();
    _sliderDebounce = Timer(const Duration(milliseconds: 100), () {
      _settingsService.setGlassMeshSpeed(speed);
      notifyListeners();
    });
  }

  // Get the current font size multiplier
  double get fontSizeMultiplier => _fontSizeFactors[_fontSize] ?? 1.0;

  ThemeData _buildLightTheme() {
    final ColorScheme colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: _primaryColor,
      onPrimary: Colors.white,
      primaryContainer: _primaryColor,
      onPrimaryContainer: Colors.white,
      secondary: _primaryColor.withOpacity(0.7),
      onSecondary: Colors.white,
      secondaryContainer: _primaryColor.withOpacity(0.7),
      onSecondaryContainer: Colors.white,
      tertiary: _primaryColor.withOpacity(0.7),
      onTertiary: Colors.white,
      tertiaryContainer: _primaryColor.withOpacity(0.7),
      onTertiaryContainer: Colors.white,
      error: Colors.red[700]!,
      onError: Colors.white,
      errorContainer: Colors.red[700]!,
      onErrorContainer: Colors.white,
      // Replace deprecated background with surface
      surface: Colors.white,
      onSurface: Colors.black,
      surfaceVariant: Colors.grey[200]!,
      onSurfaceVariant: Colors.black,
      outline: Colors.grey[400]!,
      outlineVariant: Colors.grey[400]!,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Colors.black,
      onInverseSurface: Colors.white,
      inversePrimary: Colors.white,
      surfaceTint: _primaryColor,
      // Add newer properties
      surfaceContainerHighest: Colors.white,
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
    final ColorScheme colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _primaryColor,
      onPrimary: Colors.white,
      primaryContainer: _primaryColor,
      onPrimaryContainer: Colors.white,
      secondary: _primaryColor.withOpacity(0.7),
      onSecondary: Colors.white,
      secondaryContainer: _primaryColor.withOpacity(0.7),
      onSecondaryContainer: Colors.white,
      tertiary: _primaryColor.withOpacity(0.7),
      onTertiary: Colors.white,
      tertiaryContainer: _primaryColor.withOpacity(0.7),
      onTertiaryContainer: Colors.white,
      error: Colors.red[500]!,
      onError: Colors.white,
      errorContainer: Colors.red[500]!,
      onErrorContainer: Colors.white,
      // Replace deprecated background with surface
      surface: Colors.black,
      onSurface: Colors.white,
      surfaceVariant: const Color(0xFF121212),
      onSurfaceVariant: Colors.white,
      outline: const Color(0xFF3A3A3A),
      outlineVariant: const Color(0xFF3A3A3A),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Colors.white,
      onInverseSurface: Colors.black,
      inversePrimary: Colors.white,
      surfaceTint: _primaryColor,
      // Add newer properties
      surfaceContainerHighest: Colors.white,
    );

    final baseTheme = ThemeData(
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.black,
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
        color: const Color(0xFF121212),
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
        fillColor: const Color(0xFF1E1E1E),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2C2C2C),
        disabledColor: const Color(0xFF3A3A3A),
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

  /// Build Liquid Glass theme with transparent surfaces for mesh background
  ThemeData _buildGlassTheme() {
    // Liquid Glass: dark brightness base with very light translucent surfaces
    // so the global AnimatedMeshBackground shows through everything.
    final ColorScheme colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _primaryColor,
      onPrimary: Colors.white,
      primaryContainer: _primaryColor.withOpacity(0.35),
      onPrimaryContainer: Colors.white,
      secondary: _primaryColor.withOpacity(0.7),
      onSecondary: Colors.white,
      secondaryContainer: _primaryColor.withOpacity(0.25),
      onSecondaryContainer: Colors.white,
      tertiary: _primaryColor.withOpacity(0.5),
      onTertiary: Colors.white,
      tertiaryContainer: _primaryColor.withOpacity(0.2),
      onTertiaryContainer: Colors.white,
      error: Colors.red[400]!,
      onError: Colors.white,
      errorContainer: Colors.red[400]!.withOpacity(0.25),
      onErrorContainer: Colors.white,
      // Liquid Glass surfaces — higher opacity for readability over mesh bg
      surface: Colors.white.withOpacity(0.12),
      onSurface: Colors.white,
      surfaceVariant: Colors.white.withOpacity(0.10),
      onSurfaceVariant: Colors.white.withOpacity(0.9),
      outline: Colors.white.withOpacity(0.22),
      outlineVariant: Colors.white.withOpacity(0.12),
      shadow: Colors.black.withOpacity(0.25),
      scrim: Colors.black.withOpacity(0.45),
      inverseSurface: Colors.white,
      onInverseSurface: Colors.black,
      inversePrimary: _primaryColor,
      surfaceTint: Colors.transparent,
      surfaceContainerHighest: Colors.white.withOpacity(0.14),
    );

    final baseTheme = ThemeData(
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.adaptivePlatformDensity,

      // Transparent scaffold so global mesh shows through
      scaffoldBackgroundColor: Colors.transparent,

      // ── App Bar ──
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white.withOpacity(0.14),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      // ── Elevated Button ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor.withOpacity(0.7),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999), // pill
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        ),
      ),

      // ── Outlined Button ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withOpacity(0.25)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      // ── Card ──
      cardTheme: CardTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          side: BorderSide(color: Colors.white.withOpacity(0.15), width: 0.5),
        ),
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        color: Colors.white.withOpacity(0.15),
      ),

      // ── FAB ──
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primaryColor.withOpacity(0.65),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        elevation: 0,
      ),

      // ── Text Button ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),

      // ── Icons ──
      iconTheme: const IconThemeData(color: Colors.white),

      // ── Input / Text Fields ──
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15), width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _primaryColor.withOpacity(0.7), width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
      ),

      // ── Chips ──
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withOpacity(0.14),
        disabledColor: Colors.white.withOpacity(0.06),
        selectedColor: _primaryColor.withOpacity(0.4),
        secondarySelectedColor: _primaryColor.withOpacity(0.4),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: Colors.white.withOpacity(0.18), width: 0.5),
        ),
      ),

      // ── Tab Bar ──
      tabBarTheme: TabBarTheme(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        indicator: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _primaryColor, width: 2.0),
          ),
        ),
        dividerColor: Colors.white.withOpacity(0.1),
      ),

      // ── Bottom Nav ──
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white54,
        elevation: 0,
      ),

      // ── Dialog ──
      dialogTheme: DialogTheme(
        backgroundColor: Colors.white.withOpacity(0.28),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withOpacity(0.2), width: 0.5),
        ),
        elevation: 0,
      ),

      // ── Bottom Sheet ──
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white.withOpacity(0.25),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          side: BorderSide(color: Colors.white.withOpacity(0.2), width: 0.5),
        ),
        elevation: 0,
      ),

      // ── Popup Menu ──
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white.withOpacity(0.28),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withOpacity(0.18), width: 0.5),
        ),
        elevation: 0,
      ),

      // ── Snack Bar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Colors.white.withOpacity(0.28),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withOpacity(0.15), width: 0.5),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // ── Drawer ──
      drawerTheme: DrawerThemeData(
        backgroundColor: Colors.white.withOpacity(0.18),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      // ── List Tile ──
      listTileTheme: ListTileThemeData(
        iconColor: Colors.white70,
        textColor: Colors.white,
        subtitleTextStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
      ),

      // ── Divider ──
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.12),
        thickness: 0.5,
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _primaryColor;
          return Colors.white70;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _primaryColor.withOpacity(0.5);
          }
          return Colors.white.withOpacity(0.2);
        }),
      ),

      // ── Slider ──
      sliderTheme: SliderThemeData(
        activeTrackColor: _primaryColor,
        inactiveTrackColor: Colors.white.withOpacity(0.2),
        thumbColor: _primaryColor,
        overlayColor: _primaryColor.withOpacity(0.2),
      ),

      // ── Toggle Buttons ──
      toggleButtonsTheme: ToggleButtonsThemeData(
        color: Colors.white70,
        selectedColor: Colors.white,
        fillColor: _primaryColor.withOpacity(0.35),
        borderColor: Colors.white.withOpacity(0.18),
        selectedBorderColor: _primaryColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),

      // ── Navigation Rail (desktop) ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: _primaryColor),
        unselectedIconTheme: const IconThemeData(color: Colors.white54),
        indicatorColor: _primaryColor.withOpacity(0.25),
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
