import 'package:flutter/material.dart';

import '../../app/theme.dart';

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

  static const double minHeight = 88;

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
          Icon(icon, size: 30, color: foreground),
          const SizedBox(width: 14),
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
                style: TextStyle(
                  fontSize: kind == ViButtonKind.quiet ? 17 : 21,
                  height: 1.15,
                  fontWeight: FontWeight.bold,
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
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: foreground.withValues(alpha: 0.88),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? [label, if (detail != null) detail!].join('. '),
      child: ExcludeSemantics(
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: kind == ViButtonKind.quiet
                    ? null
                    : BoxDecoration(borderRadius: BorderRadius.circular(20)),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
