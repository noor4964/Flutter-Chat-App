import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';

/// Animated gradient mesh background for Liquid Glass theme.
/// Uses large, overlapping radial-gradient blobs that drift slowly,
/// with widget-level blur for GPU-efficient compositing.
class AnimatedMeshBackground extends StatefulWidget {
  final Widget? child;
  final bool animate;
  /// Optional palette override (otherwise reads from ThemeProvider)
  final String? palette;

  const AnimatedMeshBackground({
    super.key,
    this.child,
    this.animate = true,
    this.palette,
  });

  @override
  State<AnimatedMeshBackground> createState() => _AnimatedMeshBackgroundState();
}

class _AnimatedMeshBackgroundState extends State<AnimatedMeshBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedMeshBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      widget.animate ? _controller.repeat() : _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return widget.child ?? const SizedBox.shrink();
    }

    final paletteName = widget.palette ?? themeProvider.glassPalette;
    final palette = getMeshPalette(paletteName);
    final speedFactor = themeProvider.glassMeshSpeed / 100.0;

    // Widget-level blur: Flutter's compositor caches the blurred layer,
    // so CustomPaint only draws cheap unblurred gradients each frame.
    Widget meshLayer = RepaintBoundary(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: 40,
          sigmaY: 40,
          tileMode: TileMode.decal,
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _MeshGradientPainter(
                colors: palette,
                animationValue: _controller.value * speedFactor,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );

    if (widget.child == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          meshLayer,
          // Subtle dark scrim for text readability
          Container(color: const Color(0xFF070B14).withOpacity(0.25)),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        meshLayer,
        Container(color: const Color(0xFF070B14).withOpacity(0.25)),
        widget.child!,
      ],
    );
  }
}

/// Public helper so other widgets can preview palettes.
/// Reduced to 4 colors per palette for fewer draw calls.
List<Color> getMeshPalette(String paletteName) {
  switch (paletteName) {
    case 'ocean':
      return const [
        Color(0xFF0099E5), Color(0xFF34D1BF),
        Color(0xFF0057B8), Color(0xFF1E90FF),
      ];
    case 'sunset':
      return const [
        Color(0xFFFF6B6B), Color(0xFFFFAA5C),
        Color(0xFFFF3E6D), Color(0xFFF5576C),
      ];
    case 'aurora':
      return const [
        Color(0xFF00F5D4), Color(0xFF00BBF9),
        Color(0xFFA855F7), Color(0xFF4ADE80),
      ];
    case 'lavender':
      return const [
        Color(0xFFE0AAFF), Color(0xFFC084FC),
        Color(0xFF8B5CF6), Color(0xFFD946EF),
      ];
    case 'monochrome':
      return const [
        Color(0xFF475569), Color(0xFF94A3B8),
        Color(0xFF64748B), Color(0xFFCBD5E1),
      ];
    default:
      return const [
        Color(0xFF0099E5), Color(0xFF34D1BF),
        Color(0xFF0057B8), Color(0xFF1E90FF),
      ];
  }
}

/// Custom painter: draws large soft blobs with radial gradients.
/// No canvas.saveLayer or grain — blur is handled at the widget layer.
class _MeshGradientPainter extends CustomPainter {
  final List<Color> colors;
  final double animationValue;

  _MeshGradientPainter({
    required this.colors,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dark base
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF070B14),
    );

    final paint = Paint()..style = PaintingStyle.fill;
    final maxDim = math.max(size.width, size.height);

    for (int i = 0; i < colors.length; i++) {
      final phase = (animationValue + i * 0.25) * 2 * math.pi;

      // Each blob drifts on its own Lissajous curve
      final cx = size.width * (0.2 + 0.6 * math.sin(phase + i * 1.1));
      final cy = size.height * (0.2 + 0.6 * math.cos(phase * 0.8 + i * 0.9));
      final r = maxDim * (0.45 + 0.15 * math.sin(phase * 0.5 + i * 1.3));

      final gradient = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          colors[i].withOpacity(0.55),
          colors[i].withOpacity(0.25),
          colors[i].withOpacity(0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      );

      paint.shader = gradient.createShader(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
      );

      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_MeshGradientPainter oldDelegate) {
    return (oldDelegate.animationValue - animationValue).abs() > 0.001 ||
        oldDelegate.colors != colors;
  }
}

/// Static mesh background for reduced-motion / performance fallback
class StaticMeshBackground extends StatelessWidget {
  final Widget? child;
  final String palette;

  const StaticMeshBackground({
    super.key,
    this.child,
    this.palette = 'ocean',
  });

  @override
  Widget build(BuildContext context) {
    final colors = getMeshPalette(palette);
    final container = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.first.withOpacity(0.6),
            colors[colors.length ~/ 2].withOpacity(0.4),
            colors.last.withOpacity(0.6),
          ],
        ),
      ),
    );

    if (child == null) return container;

    return Stack(
      fit: StackFit.expand,
      children: [container, child!],
    );
  }
}
