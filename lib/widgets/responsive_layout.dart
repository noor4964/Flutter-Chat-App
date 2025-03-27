import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobileView;
  final Widget desktopView;

  const ResponsiveLayout({
    Key? key,
    required this.mobileView,
    required this.desktopView,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PlatformHelper.isDesktop ? desktopView : mobileView;
  }

  // Helper method to create a split view layout for desktop
  static Widget createSplitView({
    required BuildContext context,
    required Widget leftPanel,
    required Widget rightPanel,
    required double leftPanelWidth,
  }) {
    return Row(
      children: [
        // Left panel with fixed width
        SizedBox(
          width: leftPanelWidth,
          child: leftPanel,
        ),
        // Vertical divider
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Colors.grey[300],
        ),
        // Right panel that takes remaining width
        Expanded(
          child: rightPanel,
        ),
      ],
    );
  }
}
