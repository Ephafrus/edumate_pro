import 'package:flutter/widgets.dart';

/// Breakpoints and helpers for mobile-responsive layout across web, Android
/// and iOS. Layouts adapt at [mobileMax] and [tabletMax].
class Breakpoints {
  static const double mobileMax = 600;
  static const double tabletMax = 1024;
}

enum ScreenSize { mobile, tablet, desktop }

extension ResponsiveContext on BuildContext {
  double get width => MediaQuery.sizeOf(this).width;

  ScreenSize get screenSize {
    final w = width;
    if (w < Breakpoints.mobileMax) return ScreenSize.mobile;
    if (w < Breakpoints.tabletMax) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  bool get isMobile => screenSize == ScreenSize.mobile;
  bool get isDesktop => screenSize == ScreenSize.desktop;

  /// Number of columns for grid layouts of cards.
  int get gridColumns {
    switch (screenSize) {
      case ScreenSize.mobile:
        return 1;
      case ScreenSize.tablet:
        return 2;
      case ScreenSize.desktop:
        return 3;
    }
  }
}

/// Constrains content to a comfortable reading width and centers it, so wide
/// desktop/web windows don't stretch forms edge to edge.
class ContentContainer extends StatelessWidget {
  const ContentContainer({super.key, required this.child, this.maxWidth = 900});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}
