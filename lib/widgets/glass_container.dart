import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';

// ──────────────────────────────────────────────────────────────
// Liquid Glass Component Library
//
// iOS 26-inspired translucent glass widgets. Every widget reads
// `ThemeProvider.isGlassMode`. When glass is OFF the widget falls
// back to its plain Material equivalent.
//
// Brightness-adaptive: In light mode glass uses heavier white tints
// (frosted white panels, dark text). In dark mode glass uses lighter
// tints (translucent dark panels, white text).
//
// Performance: Only large chrome elements (AppBar, BottomNav,
// Drawer, FAB, TextField) use BackdropFilter. Small/numerous
// items (Card, Button, Chip) use tint + specular gradient only.
// ──────────────────────────────────────────────────────────────

/// Core liquid-glass pane — the building block for every glass widget.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? borderRadius;
  final double? blurSigma;
  final Color? tintColor;
  final double? opacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool showBorder;
  final VoidCallback? onTap;
  final BoxShape shape;
  /// When false, skips BackdropFilter for performance in lists.
  final bool useBlur;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius,
    this.blurSigma,
    this.tintColor,
    this.opacity,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.showBorder = true,
    this.onTap,
    this.shape = BoxShape.rectangle,
    this.useBlur = true,
  });

  /// Pill-shaped constructor (capsule / stadium)
  const GlassContainer.pill({
    super.key,
    required this.child,
    this.blurSigma,
    this.tintColor,
    this.opacity,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.showBorder = true,
    this.onTap,
    this.useBlur = true,
  })  : borderRadius = 999,
        shape = BoxShape.rectangle;

  // Liquid Glass visual constants
  static const double kLightOpacity = 0.60;
  static const double kDarkOpacity = 0.18;
  static const double kDefaultBlur = 10.0;
  static const double kBorderOpacity = 0.30;
  static const double kShadowOpacity = 0.15;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.isGlassMode;
    final radius = borderRadius ?? math.max(themeProvider.borderRadius, 20.0);
    final sigma = blurSigma ?? (isGlass ? themeProvider.glassBlurSigma : kDefaultBlur);

    if (!isGlass) {
      return _buildMaterialFallback(context, radius);
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final tint = tintColor ?? Colors.white;
    final effectiveOpacity = opacity ?? (isLight ? kLightOpacity : kDarkOpacity);

    final borderColor = isLight
        ? Colors.black.withOpacity(0.08)
        : Colors.white.withOpacity(0.20);
    final shadowColor = isLight
        ? Colors.black.withOpacity(0.06)
        : Colors.black.withOpacity(kShadowOpacity);

    // Specular highlight intensity adapts to brightness
    final specularTop = isLight ? 0.06 : 0.12;
    final specularMid = isLight ? 0.02 : 0.03;

    // Liquid glass decoration
    final glassDecoration = BoxDecoration(
      color: tint.withOpacity(effectiveOpacity),
      borderRadius: BorderRadius.circular(radius),
      border: showBorder
          ? Border.all(color: borderColor, width: 0.5)
          : null,
      boxShadow: [
        BoxShadow(
          color: shadowColor,
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );

    // Specular highlight
    final specularDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(specularTop),
          Colors.white.withOpacity(specularMid),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.6],
      ),
    );

    Widget glass;

    if (useBlur && sigma > 0) {
      glass = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            width: width,
            height: height,
            decoration: glassDecoration,
            foregroundDecoration: specularDecoration,
            child: Padding(
              padding: padding ?? EdgeInsets.zero,
              child: child,
            ),
          ),
        ),
      );
    } else {
      glass = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: width,
          height: height,
          decoration: glassDecoration,
          foregroundDecoration: specularDecoration,
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      );
    }

    if (onTap != null) {
      glass = GestureDetector(onTap: onTap, child: glass);
    }

    return Container(margin: margin, child: glass);
  }

  Widget _buildMaterialFallback(BuildContext context, double radius) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                child: Padding(
                    padding: padding ?? EdgeInsets.zero, child: child),
              )
            : Padding(
                padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}

// ─── GLASS CARD ────────────────────────────────────────────────

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? opacity;

  const GlassCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.onTap,
    this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: padding ?? const EdgeInsets.all(16),
      opacity: opacity,
      useBlur: false,
      onTap: onTap,
      child: child,
    );
  }
}

// ─── GLASS SECTION — iOS Settings grouped-tile panel ───────────

class GlassSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  const GlassSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.isGlassMode;

    if (!isGlass) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 16, 8),
              child: Text(header!.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        letterSpacing: 0.5,
                      )),
            ),
          ...children,
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 6, 16, 8),
              child: Text(footer!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  )),
            ),
        ],
      );
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final headerColor = isLight
        ? Colors.black.withOpacity(0.45)
        : Colors.white.withOpacity(0.55);
    final footerColor = isLight
        ? Colors.black.withOpacity(0.35)
        : Colors.white.withOpacity(0.45);
    final dividerColor = isLight
        ? Colors.black.withOpacity(0.08)
        : Colors.white.withOpacity(0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 16, 8),
            child: Text(header!.toUpperCase(),
                style: TextStyle(
                  color: headerColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                )),
          ),
        GlassContainer(
          margin: margin ?? const EdgeInsets.symmetric(horizontal: 16),
          padding: EdgeInsets.zero,
          borderRadius: 20,
          useBlur: false,
          child: Column(
            children: List.generate(children.length, (i) {
              return Column(
                children: [
                  children[i],
                  if (i < children.length - 1)
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: dividerColor,
                      indent: 52,
                    ),
                ],
              );
            }),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 6, 16, 8),
            child: Text(footer!,
                style: TextStyle(
                  color: footerColor,
                  fontSize: 12,
                )),
          ),
      ],
    );
  }
}

// ─── GLASS LIST TILE ───────────────────────────────────────────

class GlassListTile extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;

  const GlassListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
        contentPadding: contentPadding,
      );
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final titleColor = isLight ? Colors.black87 : Colors.white;
    final subtitleColor = isLight
        ? Colors.black.withOpacity(0.5)
        : Colors.white.withOpacity(0.6);
    final iconColor = isLight ? Colors.black54 : Colors.white70;
    final trailingColor = isLight ? Colors.black38 : Colors.white54;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: contentPadding ??
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme(
                data: IconThemeData(color: iconColor, size: 24),
                child: leading!,
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      child: title!,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    DefaultTextStyle(
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 13,
                      ),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              IconTheme(
                data: IconThemeData(color: trailingColor),
                child: trailing!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── GLASS APP BAR ─────────────────────────────────────────────

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final double? elevation;
  final PreferredSizeWidget? bottom;

  const GlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.elevation,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return AppBar(
        title: title,
        actions: actions,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        elevation: elevation,
        bottom: bottom,
      );
    }

    final sigma = themeProvider.glassBlurSigma;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final bgColor = isLight
        ? Colors.white.withOpacity(0.70)
        : Colors.white.withOpacity(0.14);
    final fgColor = isLight ? Colors.black87 : Colors.white;
    final borderTopColor = isLight
        ? Colors.white.withOpacity(0.80)
        : Colors.white.withOpacity(0.35);
    final borderBottomColor = isLight
        ? Colors.black.withOpacity(0.06)
        : Colors.white.withOpacity(0.12);
    final specularOpacity = isLight ? 0.04 : 0.08;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              top: BorderSide(color: borderTopColor, width: 0.5),
              bottom: BorderSide(color: borderBottomColor, width: 0.5),
            ),
          ),
          foregroundDecoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withOpacity(specularOpacity),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: NavigationToolbar(
                    leading: leading ??
                        (automaticallyImplyLeading && Navigator.canPop(context)
                            ? IconButton(
                                icon: Icon(Icons.arrow_back_ios_new,
                                    color: fgColor, size: 20),
                                onPressed: () => Navigator.pop(context),
                              )
                            : null),
                    middle: title != null
                        ? DefaultTextStyle(
                            style: TextStyle(
                              color: fgColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            child: title!,
                          )
                        : null,
                    trailing: actions != null
                        ? Row(
                            mainAxisSize: MainAxisSize.min, children: actions!)
                        : null,
                    centerMiddle: true,
                  ),
                ),
                if (bottom != null) bottom!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
      kToolbarHeight + (bottom?.preferredSize.height ?? 0));
}

// ─── GLASS SLIVER APP BAR ──────────────────────────────────────

class GlassSliverAppBar extends StatelessWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool pinned;
  final bool floating;
  final double? expandedHeight;
  final Widget? flexibleSpace;

  const GlassSliverAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.pinned = true,
    this.floating = false,
    this.expandedHeight,
    this.flexibleSpace,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return SliverAppBar(
        title: title,
        actions: actions,
        leading: leading,
        pinned: pinned,
        floating: floating,
        expandedHeight: expandedHeight,
        flexibleSpace: flexibleSpace,
      );
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final bgColor = isLight
        ? Colors.white.withOpacity(0.70)
        : Colors.white.withOpacity(0.08);
    final fgColor = isLight ? Colors.black87 : Colors.white;

    return SliverAppBar(
      title: title != null
          ? DefaultTextStyle(
              style: TextStyle(
                  color: fgColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
              child: title!,
            )
          : null,
      actions: actions,
      leading: leading,
      pinned: pinned,
      floating: floating,
      expandedHeight: expandedHeight,
      flexibleSpace: flexibleSpace,
      backgroundColor: bgColor,
      foregroundColor: fgColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    );
  }
}

// ─── GLASS BUTTON ──────────────────────────────────────────────

class GlassButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isPrimary;
  final EdgeInsetsGeometry? padding;
  final double? width;

  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isPrimary = true,
    this.padding,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return isPrimary
          ? ElevatedButton(onPressed: onPressed, child: child)
          : TextButton(onPressed: onPressed, child: child);
    }

    final isLight = Theme.of(context).brightness == Brightness.light;

    final color = isPrimary
        ? themeProvider.primaryColor.withOpacity(0.55)
        : (isLight ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.12));
    final textColor = isPrimary
        ? Colors.white
        : (isLight ? Colors.black87 : Colors.white);
    final borderColor = isLight
        ? Colors.black.withOpacity(0.08)
        : Colors.white.withOpacity(0.20);
    final specularOpacity = isLight ? 0.08 : 0.15;

    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: width,
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withOpacity(specularOpacity),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5],
            ),
          ),
          alignment: Alignment.center,
          child: DefaultTextStyle(
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─── GLASS TEXT FIELD ──────────────────────────────────────────

class GlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? maxLines;
  final FocusNode? focusNode;
  final bool autofocus;

  const GlassTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          labelText: labelText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
        obscureText: obscureText,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        maxLines: maxLines,
        focusNode: focusNode,
        autofocus: autofocus,
      );
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? Colors.black87 : Colors.white;
    final hintColor = isLight ? Colors.black38 : Colors.white.withOpacity(0.4);
    final labelColor = isLight ? Colors.black54 : Colors.white.withOpacity(0.6);
    final fillColor = isLight
        ? Colors.white.withOpacity(0.50)
        : Colors.white.withOpacity(0.08);
    final borderColorEnabled = isLight
        ? Colors.black.withOpacity(0.08)
        : Colors.white.withOpacity(0.15);
    final iconColor = isLight ? Colors.black45 : Colors.white54;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: themeProvider.glassBlurSigma,
            sigmaY: themeProvider.glassBlurSigma),
        child: TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          maxLines: maxLines,
          focusNode: focusNode,
          autofocus: autofocus,
          style: TextStyle(color: textColor),
          cursorColor: isLight ? Colors.black54 : Colors.white70,
          decoration: InputDecoration(
            hintText: hintText,
            labelText: labelText,
            hintStyle: TextStyle(color: hintColor),
            labelStyle: TextStyle(color: labelColor),
            prefixIcon: prefixIcon != null
                ? IconTheme(
                    data: IconThemeData(color: iconColor),
                    child: prefixIcon!)
                : null,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: fillColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: borderColorEnabled, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: themeProvider.primaryColor.withOpacity(0.6), width: 1),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }
}

// ─── GLASS CHIP ────────────────────────────────────────────────

class GlassChip extends StatelessWidget {
  final Widget label;
  final Widget? avatar;
  final bool selected;
  final VoidCallback? onTap;

  const GlassChip({
    super.key,
    required this.label,
    this.avatar,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return selected
          ? FilterChip(label: label, selected: true, onSelected: (_) => onTap?.call(), avatar: avatar)
          : ActionChip(label: label, onPressed: onTap, avatar: avatar);
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final bgColor = selected
        ? themeProvider.primaryColor.withOpacity(0.40)
        : (isLight ? Colors.black.withOpacity(0.05) : Colors.white.withOpacity(0.10));
    final borderColor = isLight
        ? Colors.black.withOpacity(selected ? 0.12 : 0.06)
        : Colors.white.withOpacity(selected ? 0.25 : 0.15);
    final textColor = selected
        ? (isLight ? Colors.white : Colors.white)
        : (isLight ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.8));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[avatar!, const SizedBox(width: 6)],
            DefaultTextStyle(
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              child: label,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── GLASS DIALOG ──────────────────────────────────────────────

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

  if (!themeProvider.isGlassMode) {
    return showDialog<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
    );
  }

  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black45,
    builder: (ctx) {
      return Center(
        child: GlassContainer(
          borderRadius: 24,
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 32),
          useBlur: true,
          child: Material(
            color: Colors.transparent,
            child: builder(ctx),
          ),
        ),
      );
    },
  );
}

// ─── GLASS BOTTOM SHEET ────────────────────────────────────────

Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

  if (!themeProvider.isGlassMode) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
    );
  }

  final sigma = themeProvider.glassBlurSigma;
  final isLight = Theme.of(context).brightness == Brightness.light;

  final sheetBg = isLight
      ? Colors.white.withOpacity(0.70)
      : Colors.white.withOpacity(0.18);
  final borderColor = isLight
      ? Colors.black.withOpacity(0.08)
      : Colors.white.withOpacity(0.20);
  final handleColor = isLight
      ? Colors.black.withOpacity(0.2)
      : Colors.white.withOpacity(0.3);
  final specularOpacity = isLight ? 0.05 : 0.10;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black38,
    builder: (ctx) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(specularOpacity),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: handleColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                builder(ctx),
              ],
            ),
          ),
        ),
      );
    },
  );
}
