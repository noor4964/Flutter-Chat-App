import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';

// ──────────────────────────────────────────────────────────────
// Liquid Glass Scaffold & Navigation widgets
//
// These wrappers make the Scaffold transparent so glass
// BackdropFilter widgets can blur actual underlying content,
// and apply liquid glass treatment to chrome elements like
// nav bars, drawers, and FABs.
//
// Brightness-adaptive: light mode = frosted white, dark mode =
// translucent dark.
// ──────────────────────────────────────────────────────────────

/// Drop-in Scaffold replacement.
/// In glass mode → transparent BG + extendBody so glass widgets can blur content.
/// In non-glass mode → delegates to a plain Scaffold unchanged.
class GlassScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool extendBodyBehindAppBar;
  final bool extendBody;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;

  const GlassScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.drawer,
    this.endDrawer,
    this.extendBodyBehindAppBar = false,
    this.extendBody = false,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.isGlassMode;

    if (!isGlass) {
      return Scaffold(
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
        drawer: drawer,
        endDrawer: endDrawer,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        extendBody: extendBody,
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      );
    }

    // Glass mode: transparent so glass widgets blur actual content behind them
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      extendBody: true,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      drawer: drawer,
      endDrawer: endDrawer,
    );
  }
}

// ─── GLASS BOTTOM NAV BAR — Liquid Glass style ──────────────────

class GlassBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavigationBarItem> items;

  const GlassBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        items: items,
      );
    }

    final sigma = themeProvider.glassBlurSigma;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final bgColor = isLight
        ? Colors.white.withOpacity(0.70)
        : Colors.white.withOpacity(0.14);
    final borderTopColor = isLight
        ? Colors.black.withOpacity(0.06)
        : Colors.white.withOpacity(0.30);
    final specularOpacity = isLight ? 0.04 : 0.10;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              top: BorderSide(color: borderTopColor, width: 0.75),
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
              stops: const [0.0, 0.4],
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 58,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                    items.length, (i) => _buildNavItem(context, i)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index) {
    final item = items[index];
    final isSelected = index == currentIndex;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isLight = Theme.of(context).brightness == Brightness.light;

    final selectedColor = isLight ? themeProvider.primaryColor : Colors.white;
    final unselectedColor = isLight ? Colors.black45 : Colors.white54;
    final pillColor = isLight
        ? themeProvider.primaryColor.withOpacity(0.12)
        : themeProvider.primaryColor.withOpacity(0.30);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? pillColor : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: isSelected ? selectedColor : unselectedColor,
                  size: 22,
                ),
                child: isSelected
                    ? (item.activeIcon)
                    : item.icon,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label ?? '',
              style: TextStyle(
                color: isSelected ? selectedColor : unselectedColor,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── GLASS FLOATING ACTION BUTTON ──────────────────────────────

class GlassFloatingActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;

  const GlassFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return FloatingActionButton(
        onPressed: onPressed,
        tooltip: tooltip,
        child: child,
      );
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final borderColor = isLight
        ? Colors.black.withOpacity(0.08)
        : Colors.white.withOpacity(0.20);
    final specularOpacity = isLight ? 0.10 : 0.20;

    Widget button = GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: themeProvider.glassBlurSigma,
              sigmaY: themeProvider.glassBlurSigma),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: themeProvider.primaryColor.withOpacity(0.50),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: themeProvider.primaryColor.withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
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
            child: IconTheme(
              data: const IconThemeData(color: Colors.white, size: 24),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

// ─── GLASS DRAWER ──────────────────────────────────────────────

class GlassDrawer extends StatelessWidget {
  final Widget child;
  final double? width;

  const GlassDrawer({
    super.key,
    required this.child,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isGlassMode) {
      return Drawer(width: width, child: child);
    }

    final drawerWidth = width ?? MediaQuery.of(context).size.width * 0.78;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final bgColor = isLight
        ? Colors.white.withOpacity(0.70)
        : Colors.white.withOpacity(0.16);
    final borderColor = isLight
        ? Colors.black.withOpacity(0.06)
        : Colors.white.withOpacity(0.25);
    final specularOpacity = isLight ? 0.03 : 0.06;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: themeProvider.glassBlurSigma,
            sigmaY: themeProvider.glassBlurSigma),
        child: Container(
          width: drawerWidth,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              right: BorderSide(color: borderColor, width: 0.75),
            ),
          ),
          foregroundDecoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [
                Colors.white.withOpacity(specularOpacity),
                Colors.transparent,
              ],
              stops: const [0.0, 0.3],
            ),
          ),
          child: SafeArea(child: child),
        ),
      ),
    );
  }
}

// ─── GLASS PAGE WRAPPER ────────────────────────────────────────

/// Legacy helper — wraps content so glassmorphism appears.
/// Now a no-op passthrough since glass is handled at widget level.
class GlassPageWrapper extends StatelessWidget {
  final Widget child;

  const GlassPageWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
