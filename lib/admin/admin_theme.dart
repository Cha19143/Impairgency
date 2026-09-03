import 'package:flutter/material.dart';

import '../app/theme.dart';

/// The dashboard's palette.
///
/// §4: "The Admin Dashboard can use a more detailed interface because it will
/// primarily be used by administrators and staff." So this is the one surface
/// in the project not built under the constraints of the app — dense, light,
/// and read with eyes rather than ears.
///
/// It keeps ImpairGency's navy for chrome so the two feel like one product, and
/// puts the data on a light ground where a table of numbers is legible.
abstract final class AdminColors {
  static const Color chrome = AppColors.navy;
  static const Color chromeText = Color(0xFF93A7D4);
  static const Color accent = AppColors.cyan;

  static const Color canvas = Color(0xFFF2F5FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFDEE4EF);
  static const Color ink = Color(0xFF0E1626);
  static const Color inkMuted = Color(0xFF6B7893);

  /// Semantic, and separate from the accent. Nothing decorative is ever red.
  static const Color good = Color(0xFF0F6B3F);
  static const Color warn = Color(0xFF8A5600);
  static const Color bad = Color(0xFF9C1F2B);
}

/// No animation between panes.
///
/// A dashboard is a set of views, not a stack of pages. Sliding one over
/// another suggests a journey the user is not making, and after a sidebar click
/// the animation is pure latency: the destination is already decided and the
/// user is waiting to read it.
class _InstantPageTransitions extends PageTransitionsBuilder {
  const _InstantPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

ThemeData buildAdminTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AdminColors.chrome,
      brightness: Brightness.light,
    ).copyWith(surface: AdminColors.canvas),
    scaffoldBackgroundColor: AdminColors.canvas,
  );
  return base.copyWith(
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const _InstantPageTransitions(),
      },
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AdminColors.ink,
      displayColor: AdminColors.ink,
    ),
    cardTheme: const CardThemeData(
      color: AdminColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
  );
}
