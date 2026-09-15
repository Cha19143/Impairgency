import 'package:flutter/material.dart';

import 'vi_button.dart';

/// Buttons that share a row only when every label still reads as words.
///
/// Read Text put Pause, Say that again and Next line side by side. On a
/// 360 dp phone each button then had about sixteen pixels for its label, and
/// the tester's screenshot showed "Pa / us / e" and "Sa / y / th / at". A fixed
/// breakpoint would only move that failure to a larger text size, so this
/// measures instead: the most buttons per row at which every label keeps its
/// longest word on one line and wraps to no more than two, at the text scale
/// the user actually set. Phones end up with a stack of full-size buttons,
/// which is also the easier thing to find by sweeping a finger.
class ViButtonGroup extends StatelessWidget {
  const ViButtonGroup({super.key, required this.buttons, this.gap = 10});

  final List<ViButton> buttons;

  /// Space between buttons in a row.
  final double gap;

  /// How many of [buttons] fit on one row [width] wide, at [textScaler].
  static int perRow({
    required List<ViButton> buttons,
    required double width,
    required TextScaler textScaler,
    TextDirection textDirection = TextDirection.ltr,
    double gap = 10,
  }) {
    for (var count = buttons.length; count > 1; count--) {
      final cell = (width - gap * (count - 1)) / count;
      if (buttons.every((b) => _fits(b, cell, textScaler, textDirection))) {
        return count;
      }
    }
    return 1;
  }

  static bool _fits(ViButton button, double cell, TextScaler scaler,
      TextDirection direction) {
    final room = button.labelWidthIn(cell);
    if (room <= 0) return false;

    double widest(String text, TextStyle style) {
      var max = 0.0;
      for (final word in text.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        if (painter.width > max) max = painter.width;
        painter.dispose();
      }
      return max;
    }

    final labelStyle = ViButton.labelStyle(button.kind);
    if (widest(button.label, labelStyle) > room) return false;
    final detail = button.detail;
    if (detail != null && widest(detail, ViButton.detailStyle) > room) {
      return false;
    }

    final whole = TextPainter(
      text: TextSpan(text: button.label, style: labelStyle),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: room);
    final lines = whole.computeLineMetrics().length;
    whole.dispose();
    return lines <= 2;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final count = perRow(
            buttons: buttons,
            width: constraints.maxWidth,
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context),
            gap: gap,
          );
          if (count == 1) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: buttons,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var start = 0; start < buttons.length; start += count)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = start;
                        i < start + count && i < buttons.length;
                        i++) ...[
                      if (i > start) SizedBox(width: gap),
                      Expanded(child: buttons[i]),
                    ],
                  ],
                ),
            ],
          );
        },
      );
}
