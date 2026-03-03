import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/widgets/glass_scaffold.dart';
import 'package:flutter_chat_app/widgets/glass_container.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  // Preset accent colors
  static const List<Color> _presetColors = [
    Colors.deepPurple,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.pink,
    Colors.indigo,
    Colors.cyan,
    Colors.amber,
  ];

  // Responsive breakpoint
  static const double _wideBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return GlassScaffold(
      appBar: themeProvider.isGlassMode
          ? GlassAppBar(title: const Text('Appearance'))
          : AppBar(
              title: const Text('Appearance'),
              centerTitle: true,
              elevation: 0,
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideBreakpoint;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildSettingsContent(themeProvider, colorScheme),
                ),
                SizedBox(
                  width: 340,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildPreviewPanel(themeProvider, colorScheme),
                  ),
                ),
              ],
            );
          } else {
            return _buildSettingsContent(themeProvider, colorScheme,
                showPreviewInline: true);
          }
        },
      ),
    );
  }

  Widget _buildSettingsContent(
      ThemeProvider themeProvider, ColorScheme colorScheme,
      {bool showPreviewInline = false}) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (showPreviewInline) ...[
          _buildPreviewCard(themeProvider, colorScheme),
          const SizedBox(height: 16),
        ],

        // ── Theme Mode ──
        _buildSectionHeader('Theme Mode'),
        _buildCard([
          _buildThemeSelector(themeProvider),
        ]),
        const SizedBox(height: 12),

        // ── Liquid Glass Toggle ──
        _buildSectionHeader('Liquid Glass'),
        _buildCard([
          SwitchListTile(
            title: const Text('Liquid Glass'),
            subtitle: const Text('Enable frosted glass surfaces'),
            secondary: Icon(
              Icons.blur_on_rounded,
              color: themeProvider.isGlassMode
                  ? colorScheme.primary
                  : null,
            ),
            value: themeProvider.isGlassMode,
            activeColor: colorScheme.primary,
            onChanged: (value) => themeProvider.setLiquidGlass(value),
          ),
        ]),

        // ── Glass Blur Slider (smooth show/hide) ──
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: themeProvider.isGlassMode
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    _buildCard([
                      _buildGlassBlurSlider(themeProvider),
                    ]),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),

        // ── Accent Color ──
        _buildSectionHeader('Accent Color'),
        _buildCard([
          _buildColorSwatches(themeProvider),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: themeProvider.primaryColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
            ),
            title: const Text('Custom Color'),
            subtitle: Text(
              '#${themeProvider.primaryColor.value.toRadixString(16).substring(2).toUpperCase()}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.colorize, size: 20),
            onTap: () => _showColorPicker(themeProvider),
          ),
        ]),
        const SizedBox(height: 12),

        // ── Font Size ──
        _buildSectionHeader('Font Size'),
        _buildCard([
          _buildFontSizeSelector(themeProvider),
        ]),
        const SizedBox(height: 12),

        // ── Visual Effects ──
        _buildSectionHeader('Visual Effects'),
        _buildCard([
          SwitchListTile(
            title: const Text('Animations'),
            subtitle: const Text('Enable transitions and motion effects'),
            value: themeProvider.useAnimations,
            activeColor: colorScheme.primary,
            onChanged: (value) => themeProvider.setUseAnimations(value),
          ),
          if (!themeProvider.isGlassMode) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              title: const Text('Blur Effects'),
              subtitle: const Text('Frosted glass on modals and cards'),
              value: themeProvider.useBlurEffects,
              activeColor: colorScheme.primary,
              onChanged: (value) => themeProvider.setUseBlurEffects(value),
            ),
          ],
        ]),
        const SizedBox(height: 12),

        // ── Border Radius ──
        _buildSectionHeader('Corner Radius'),
        _buildCard([
          _buildBorderRadiusSlider(themeProvider),
        ]),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Preview Panel ──

  Widget _buildPreviewPanel(
      ThemeProvider themeProvider, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PREVIEW',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
                letterSpacing: 0.8)),
        const SizedBox(height: 12),
        _buildPreviewCard(themeProvider, colorScheme),
      ],
    );
  }

  // ── Preview Card ──

  Widget _buildPreviewCard(ThemeProvider themeProvider, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(themeProvider.borderRadius)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preview',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600])),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(
                          themeProvider.borderRadius)),
                  child: const Text('Hey! How are you?'),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(
                          themeProvider.borderRadius)),
                  child: Text("I'm doing great!",
                      style: TextStyle(color: cs.onPrimary)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.tonal(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                themeProvider.borderRadius * 0.6))),
                    child: const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Theme Selector — Light / Dark ──

  Widget _buildThemeSelector(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildThemePreviewCard(
            label: 'Light',
            icon: Icons.light_mode_rounded,
            selected: themeProvider.themeStyle == ThemeStyle.light,
            onTap: () => themeProvider.setThemeStyle(ThemeStyle.light),
            previewGradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF8F9FA), Color(0xFFE9ECEF)],
            ),
            iconColor: Colors.amber,
          ),
          const SizedBox(width: 10),
          _buildThemePreviewCard(
            label: 'Dark',
            icon: Icons.dark_mode_rounded,
            selected: themeProvider.themeStyle == ThemeStyle.dark,
            onTap: () => themeProvider.setThemeStyle(ThemeStyle.dark),
            previewGradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            ),
            iconColor: Colors.indigo.shade200,
          ),
        ],
      ),
    );
  }

  Widget _buildThemePreviewCard({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required LinearGradient previewGradient,
    Color? iconColor,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : Colors.grey.withOpacity(0.25),
              width: selected ? 2.0 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: cs.primary.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Preview area
              Container(
                height: 64,
                decoration: BoxDecoration(gradient: previewGradient),
                child: Center(
                  child: Icon(icon,
                      size: 28,
                      color: selected
                          ? (iconColor ?? Colors.white)
                          : Colors.grey[500]),
                ),
              ),
              // Label area
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? cs.primary.withOpacity(0.08)
                      : Colors.transparent,
                ),
                child: Column(
                  children: [
                    Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? cs.primary : Colors.grey[600],
                        )),
                    if (selected) ...[
                      const SizedBox(height: 1),
                      Icon(Icons.check_circle,
                          size: 12, color: cs.primary),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Glass Clarity Slider ──

  Widget _buildGlassBlurSlider(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Glass Clarity',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600])),
              Text(
                  themeProvider.glassBlurSigma == 0
                      ? 'Sharp'
                      : '${themeProvider.glassBlurSigma.round()}',
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey[500])),
            ],
          ),
          Row(
            children: [
              Text('Sharp',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey[500])),
              Expanded(
                child: Slider(
                  value: themeProvider.glassBlurSigma.clamp(0, 20),
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChanged: (value) =>
                      themeProvider.setGlassBlurSigma(value),
                ),
              ),
              Text('Frosted',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }

  // ── Color Swatches ──

  Widget _buildColorSwatches(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _presetColors.map((color) {
          final isSelected =
              themeProvider.primaryColor.value == color.value;
          return GestureDetector(
            onTap: () => themeProvider.setPrimaryColor(color),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Colors.white
                      : Colors.transparent,
                  width: 3,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: color.withOpacity(0.5),
                            blurRadius: 8)
                      ]
                    : [],
              ),
              child: isSelected
                  ? const Icon(Icons.check,
                      color: Colors.white, size: 20)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Color Picker Dialog ──

  void _showColorPicker(ThemeProvider themeProvider) {
    Color tempColor = themeProvider.primaryColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: tempColor,
            onColorChanged: (color) => tempColor = color,
            enableAlpha: false,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              themeProvider.setPrimaryColor(tempColor);
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ── Font Size Selector ──

  Widget _buildFontSizeSelector(ThemeProvider themeProvider) {
    const sizes = ['Small', 'Medium', 'Large', 'Extra Large'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: sizes.map((size) {
              final isSelected = themeProvider.fontSize == size;
              final cs = Theme.of(context).colorScheme;
              return Expanded(
                child: GestureDetector(
                  onTap: () => themeProvider.setFontSize(size),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 3),
                    padding:
                        const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cs.primary.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? cs.primary
                            : Colors.grey.withOpacity(0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        size == 'Extra Large' ? 'XL' : size[0],
                        style: TextStyle(
                          fontSize: _fontSizePreview(size),
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? cs.primary
                              : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(themeProvider.fontSize,
              style:
                  TextStyle(fontSize: 13, color: Colors.grey[600])),
        ],
      ),
    );
  }

  double _fontSizePreview(String size) {
    switch (size) {
      case 'Small':
        return 12;
      case 'Medium':
        return 15;
      case 'Large':
        return 18;
      case 'Extra Large':
        return 21;
      default:
        return 15;
    }
  }

  // ── Border Radius Slider ──

  Widget _buildBorderRadiusSlider(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.crop_square, size: 20),
              Expanded(
                child: Slider(
                  value: themeProvider.borderRadius,
                  min: 0,
                  max: 28,
                  divisions: 14,
                  label: '${themeProvider.borderRadius.round()}',
                  onChanged: (value) =>
                      themeProvider.setBorderRadius(value),
                ),
              ),
              const Icon(Icons.circle_outlined, size: 20),
            ],
          ),
          Text('Radius: ${themeProvider.borderRadius.round()}px',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // ── Helpers ──

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color:
                  Theme.of(context).dividerColor.withOpacity(0.15)),
        ),
        child: Column(children: children),
      ),
    );
  }
}
