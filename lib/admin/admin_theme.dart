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

  /// Ink for use *on* [accent]. The pairing the app already uses, at 14.8:1.
  static const Color inkOnAccent = AppColors.inkOnLight;

  static const Color canvas = Color(0xFFF2F5FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFDEE4EF);

  /// The ground inside a form field, and behind a line of code.
  static const Color field = Color(0xFFF7F9FC);

  static const Color ink = Color(0xFF0E1626);

  /// Supporting text. Darkened from #6B7893, which measured 4.4:1 on a white
  /// card and 4.2:1 inside a field — under AA, on the one surface in the
  /// project that audits its own contrast.
  static const Color inkMuted = Color(0xFF616E88);

  /// Semantic, and separate from the accent. Nothing decorative is ever red.
  static const Color good = Color(0xFF0F6B3F);
  static const Color warn = Color(0xFF8A5600);
  static const Color bad = Color(0xFF9C1F2B);

  /// The ground [bad] is written on when a whole banner has to carry it.
  static const Color badTint = Color(0xFFFEF1F2);
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
  const fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: AdminColors.line),
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
    // Set here rather than on each screen, so a field in a dialog nobody
    // remembers to restyle still looks like a field on the sign-in page.
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AdminColors.field,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      disabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        // Navy rather than the cyan accent: a focus ring has to be visible
        // against what is around it, and cyan on white is 1.3:1.
        borderSide: BorderSide(color: AdminColors.chrome, width: 1.8),
      ),
      labelStyle: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: AdminColors.inkMuted,
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: AdminColors.inkMuted,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      helperStyle: TextStyle(fontSize: 11.5, color: AdminColors.inkMuted),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 17),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AdminColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.bold,
        color: AdminColors.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AdminColors.chrome,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminColors.ink,
        side: const BorderSide(color: AdminColors.line),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AdminColors.chrome,
        textStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
