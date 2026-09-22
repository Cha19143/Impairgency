import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/widgets/labelled_control.dart';
import 'press_by_voice.dart';

/// How a button looks, which is also what it means.
enum ViButtonKind {
  /// The thing this screen is for.
  primary,

  /// A real alternative, not a lesser one.
  secondary,

  /// Emergency. Never used for anything that is not one.
  emergency,

  /// Skipping, or going back. Deliberately quieter, and never the same shape
  /// as an action that does something.
  quiet,
}

/// A control sized for someone who cannot see where they are aiming.
///
/// The floor is 88dp, not the platform's 48. Someone touching a screen they
/// cannot see is not aiming, they are sweeping — and a target they can find by
/// sweeping is a different size from a target they can hit by looking.
class ViButton extends StatelessWidget {
  const ViButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ViButtonKind.primary,
    this.icon,
    this.detail,
    this.semanticLabel,
    this.pressByVoice = true,
  });

  final String label;

  /// A second line, for what the choice means. Spoken as part of the button.
  final String? detail;

  final VoidCallback? onPressed;
  final ViButtonKind kind;
  final IconData? icon;

  /// Overrides what a screen reader announces. Defaults to label plus detail,
  /// which is almost always what it should be.
  final String? semanticLabel;

  /// Whether saying [label] presses it. Off for the microphone button, whose
  /// label is what it is doing rather than a thing to do.
  final bool pressByVoice;

  static const double minHeight = 88;

  /// Padding either side of the content, the icon, and the space after it.
  /// Public so [ViButtonGroup] measures the room a label really gets.
  static const double horizontalPadding = 20;
  static const double iconSize = 30;
  static const double iconGap = 14;

  /// How wide the label may be in a button [width] wide.
  double labelWidthIn(double width) =>
      width - 2 * horizontalPadding - (icon == null ? 0 : iconSize + iconGap);

  static TextStyle labelStyle(ViButtonKind kind) => TextStyle(
        fontSize: kind == ViButtonKind.quiet ? 17 : 21,
        height: 1.15,
        fontWeight: FontWeight.bold,
      );

  static const TextStyle detailStyle = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (kind) {
      ViButtonKind.primary => (AppColors.cyan, AppColors.inkOnLight),
      ViButtonKind.secondary => (AppColors.blue, AppColors.textPrimary),
      ViButtonKind.emergency => (AppColors.red, AppColors.inkOnLight),
      ViButtonKind.quiet => (Colors.transparent, AppColors.textSecondary),
    };

    final content = Row(
      mainAxisAlignment:
          kind == ViButtonKind.quiet ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: foreground),
          const SizedBox(width: iconGap),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: kind == ViButtonKind.quiet
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: labelStyle(kind).copyWith(
                  color: foreground,
                  decoration:
                      kind == ViButtonKind.quiet ? TextDecoration.underline : null,
                  decorationColor: foreground,
                ),
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    detail!,
                    style: detailStyle.copyWith(
                      color: foreground.withValues(alpha: 0.88),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final control = LabelledControl(
      label: semanticLabel ?? [label, if (detail != null) detail!].join('. '),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: BoxConstraints(
                minHeight: kind == ViButtonKind.quiet ? 56 : minHeight,
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: 14),
              decoration: kind == ViButtonKind.quiet
                  ? null
                  : BoxDecoration(borderRadius: BorderRadius.circular(20)),
              child: content,
            ),
          ),
        ),
      ),
    );
    return pressByVoice
        ? PressByVoice(label: label, onPressed: onPressed, child: control)
        : control;
  }
}
