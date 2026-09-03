/// WCAG relative-luminance and contrast maths.
///
/// Plain integers rather than `Color` so this stays outside Flutter and can be
/// unit tested cheaply. The requirements document asks for high contrast in
/// §4; this is the file that lets a test enforce it instead of a reviewer
/// noticing it.
library;

import 'dart:math' as math;

double _channel(int eightBit) {
  final c = eightBit / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) as double;
}

/// WCAG 2.1 relative luminance of an opaque 0xRRGGBB or 0xAARRGGBB value.
double relativeLuminance(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b);
}

/// Contrast ratio between two opaque colours, from 1.0 to 21.0.
double contrastRatio(int a, int b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// WCAG AA for body text.
const double kAaNormalText = 4.5;

/// WCAG AA for text at 18.66px bold or 24px regular and above, and for
/// meaningful non-text elements such as focus rings and icons.
const double kAaLargeText = 3.0;

/// WCAG AAA for body text. ImpairGency's buttons clear this, and should: the
/// people using them are the reason the app exists.
const double kAaaNormalText = 7.0;
