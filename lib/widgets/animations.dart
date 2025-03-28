import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:provider/provider.dart';

/// A collection of animation widgets for enhancing the UI

/// Animates a child when it first appears with a fade-in effect
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  const FadeIn({
    Key? key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.delay = Duration.zero,
    this.curve = Curves.easeInOut,
  }) : super(key: key);

  @override
  FadeInState createState() => FadeInState();
}

class FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
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

    // Skip animation if animations are disabled
    if (!themeProvider.useAnimations) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _animation,
      child: widget.child,
    );
  }
}

/// Animates a child sliding in from a direction
class SlideIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final Offset startOffset;

  const SlideIn({
    Key? key,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
    this.delay = Duration.zero,
    this.curve = Curves.easeOutQuad,
    this.startOffset = const Offset(0.0, 0.5),
  }) : super(key: key);

  // Convenience constructors for common directions
  factory SlideIn.fromLeft({
    Key? key,
    required Widget child,
    Duration duration = const Duration(milliseconds: 400),
    Duration delay = Duration.zero,
    Curve curve = Curves.easeOutQuad,
  }) {
    return SlideIn(
      key: key,
      child: child,
      duration: duration,
      delay: delay,
      curve: curve,
      startOffset: const Offset(-1.0, 0.0),
    );
  }

  factory SlideIn.fromRight({
    Key? key,
    required Widget child,
    Duration duration = const Duration(milliseconds: 400),
    Duration delay = Duration.zero,
    Curve curve = Curves.easeOutQuad,
  }) {
    return SlideIn(
      key: key,
      child: child,
      duration: duration,
      delay: delay,
      curve: curve,
      startOffset: const Offset(1.0, 0.0),
    );
  }

  factory SlideIn.fromTop({
    Key? key,
    required Widget child,
    Duration duration = const Duration(milliseconds: 400),
    Duration delay = Duration.zero,
    Curve curve = Curves.easeOutQuad,
  }) {
    return SlideIn(
      key: key,
      child: child,
      duration: duration,
      delay: delay,
      curve: curve,
      startOffset: const Offset(0.0, -1.0),
    );
  }

  factory SlideIn.fromBottom({
    Key? key,
    required Widget child,
    Duration duration = const Duration(milliseconds: 400),
    Duration delay = Duration.zero,
    Curve curve = Curves.easeOutQuad,
  }) {
    return SlideIn(
      key: key,
      child: child,
      duration: duration,
      delay: delay,
      curve: curve,
      startOffset: const Offset(0.0, 1.0),
    );
  }

  @override
  SlideInState createState() => SlideInState();
}

class SlideInState extends State<SlideIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = Tween<Offset>(
      begin: widget.startOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    ));

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
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

    // Skip animation if animations are disabled
    if (!themeProvider.useAnimations) {
      return widget.child;
    }

    return SlideTransition(
      position: _animation,
      child: widget.child,
    );
  }
}

/// Animates a list of children with staggered animations
class StaggeredList extends StatelessWidget {
  final List<Widget> children;
  final Duration itemDuration;
  final Duration delay;
  final Curve curve;
  final bool fromBottom;

  const StaggeredList({
    Key? key,
    required this.children,
    this.itemDuration = const Duration(milliseconds: 300),
    this.delay = const Duration(milliseconds: 50),
    this.curve = Curves.easeOut,
    this.fromBottom = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Skip animation if animations are disabled
    if (!themeProvider.useAnimations) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _animateChildren(),
    );
  }

  List<Widget> _animateChildren() {
    return List.generate(children.length, (index) {
      final itemDelay = Duration(milliseconds: delay.inMilliseconds * index);

      return SlideIn(
        duration: itemDuration,
        delay: itemDelay,
        startOffset: Offset(0.0, fromBottom ? 0.3 : -0.3),
        child: FadeIn(
          duration: itemDuration,
          delay: itemDelay,
          child: children[index],
        ),
      );
    });
  }
}

/// A button that scales when pressed
class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleValue;
  final Duration duration;

  const ScaleButton({
    Key? key,
    required this.child,
    this.onTap,
    this.scaleValue = 0.95,
    this.duration = const Duration(milliseconds: 150),
  }) : super(key: key);

  @override
  ScaleButtonState createState() => ScaleButtonState();
}

class ScaleButtonState extends State<ScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleValue,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // If animations are disabled, use a simple GestureDetector
    if (!themeProvider.useAnimations) {
      return GestureDetector(
        onTap: widget.onTap,
        child: widget.child,
      );
    }

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        if (widget.onTap != null) {
          widget.onTap!();
        }
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: widget.child,
          );
        },
      ),
    );
  }
}

/// A pulsing animation for attention-grabbing elements
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double maxScale;
  final bool repeat;

  const PulseAnimation({
    Key? key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    this.maxScale = 1.1,
    this.repeat = true,
  }) : super(key: key);

  @override
  PulseAnimationState createState() => PulseAnimationState();
}

class PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = Tween<double>(
      begin: 1.0,
      end: widget.maxScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.repeat) {
      _controller.repeat(reverse: true);
    } else {
      _controller.forward();
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

    // Skip animation if animations are disabled
    if (!themeProvider.useAnimations) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: widget.child,
        );
      },
    );
  }
}

/// A customizable shimmer loading effect
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;
  final bool enabled;

  const ShimmerLoading({
    Key? key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
    this.enabled = true,
  }) : super(key: key);

  @override
  ShimmerLoadingState createState() => ShimmerLoadingState();
}

class ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );

    if (widget.enabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(ShimmerLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
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

    // Skip animation if animations are disabled or not enabled
    if (!themeProvider.useAnimations || !widget.enabled) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final baseColor = widget.baseColor ??
        (theme.brightness == Brightness.light
            ? Colors.grey[300]!
            : Colors.grey[700]!);
    final highlightColor = widget.highlightColor ??
        (theme.brightness == Brightness.light
            ? Colors.grey[100]!
            : Colors.grey[600]!);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: _SlidingGradientTransform(
                slidePercent: _animation.value,
              ),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({
    required this.slidePercent,
  });

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * slidePercent,
      0.0,
      0.0,
    );
  }
}

/// A background blur effect container
class BlurContainer extends StatelessWidget {
  final Widget child;
  final double blurRadius;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;

  const BlurContainer({
    Key? key,
    required this.child,
    this.blurRadius = 10.0,
    this.backgroundColor,
    this.borderRadius,
    this.padding = const EdgeInsets.all(16.0),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);

    // Default background color based on theme
    final bgColor = backgroundColor ??
        (theme.brightness == Brightness.light
            ? Colors.white.withOpacity(0.7)
            : Colors.black.withOpacity(0.7));

    // Use border radius from theme provider if none is provided
    final radius =
        borderRadius ?? BorderRadius.circular(themeProvider.borderRadius);

    // Skip blur if blur effects are disabled
    if (!themeProvider.useBlurEffects) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: bgColor.withOpacity(1.0), // Solid color if blur is disabled
          borderRadius: radius,
        ),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurRadius,
          sigmaY: blurRadius,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: radius,
          ),
          child: child,
        ),
      ),
    );
  }
}
