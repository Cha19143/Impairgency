import 'package:flutter/material.dart';

/// ImpairGency's palette, carried over from the original app because it was
/// the right instinct: a dark ground with saturated, unmistakable actions.
///
/// What is *not* carried over is how the old app coloured button labels. It set
/// them to the theme's `secondaryBackground`, which resolves to white in the
/// light theme - so the largest, most important controls in an app for
/// partially sighted users rendered white text on `#00FFFF`, about 1.1:1.
///
/// Every pairing below is asserted in `test/core/contrast_test.dart`. If someone
/// changes one of these values and breaks the ratio, the test fails rather than
/// the user.
abstract final class AppColors {
  /// Page ground. Every screen sits on this.
  static const Color navy = Color(0xFF0A1A3F);
  static const Color navyRaised = Color(0xFF122A5C);
  static const Color hairline = Color(0xFF2B4488);

  /// Primary action. Scan, continue, confirm.
  static const Color cyan = Color(0xFF00FFFF);

  /// Secondary action.
  static const Color blue = Color(0xFF1E3A8A);

  /// Emergency only. Never used decoratively - if it is red, it is urgent.
  static const Color red = Color(0xFFFF5963);

  static const Color amber = Color(0xFFF9CF58);
  static const Color green = Color(0xFF3ED598);

  /// Ink for use *on* the light, saturated fills. Dark on purpose.
  static const Color inkOnLight = Color(0xFF04122E);

  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Supporting text. Still clears AA on [navy] - a "muted" colour that fails
  /// contrast is not muted, it is broken.
  static const Color textSecondary = Color(0xFFB9C7E8);
}

/// The foreground/background pairs the app actually renders, named so a test
/// can walk them. Add a pair here whenever you add one to the UI.
const Map<String, (int foreground, int background)> kContrastPairs = {
  'body text on ground': (0xFFFFFFFF, 0xFF0A1A3F),
  'supporting text on ground': (0xFFB9C7E8, 0xFF0A1A3F),
  'label on primary action': (0xFF04122E, 0xFF00FFFF),
  'label on secondary action': (0xFFFFFFFF, 0xFF1E3A8A),
  'label on emergency action': (0xFF04122E, 0xFFFF5963),
  'label on raised surface': (0xFFFFFFFF, 0xFF122A5C),
  'success text on ground': (0xFF3ED598, 0xFF0A1A3F),
  'warning text on ground': (0xFFF9CF58, 0xFF0A1A3F),
};

/// Minimum touch target. The platform floor is 48dp; this app's users are
/// aiming without sight, so the floor here is higher and the buttons are
/// bigger still.
const double kMinTargetSize = 64.0;

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.cyan,
    onPrimary: AppColors.inkOnLight,
    secondary: AppColors.blue,
    onSecondary: AppColors.textPrimary,
    error: AppColors.red,
    onError: AppColors.inkOnLight,
    surface: AppColors.navy,
    onSurface: AppColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.navy,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: AppColors.textPrimary,
      centerTitle: false,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(kMinTargetSize + 36),
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.inkOnLight,
        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
  );
}
