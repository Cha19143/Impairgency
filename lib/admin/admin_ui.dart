import 'package:flutter/material.dart';

import 'admin_theme.dart';


/// The surfaces the dashboard is made of.
///
/// Overview, Users and System health each grew their own card, their own
/// eyebrow heading and their own stat tile, which drifted: three radii, two
/// paddings, two ways of colouring a number that means something is wrong.
/// One set of parts here means a change to the dashboard's look is a change in
/// one file, and a new screen looks like the rest of it by default.

/// What a colour is saying, rather than which colour it is.
///
/// Kept semantic on purpose: nothing on this dashboard is red for emphasis.
enum AdminTone { neutral, good, warn, bad }

extension AdminToneColours on AdminTone {
  /// Ink for a value, an icon, or a pill label in this tone.
  Color get ink => switch (this) {
        AdminTone.neutral => AdminColors.chrome,
        AdminTone.good => AdminColors.good,
        AdminTone.warn => AdminColors.warn,
        AdminTone.bad => AdminColors.bad,
      };

  /// The ground that ink is written on. Every pairing clears WCAG AA.
  Color get tint => switch (this) {
        AdminTone.neutral => const Color(0xFFEEF2FA),
        AdminTone.good => const Color(0xFFE6F4EC),
        AdminTone.warn => const Color(0xFFFDF3E2),
        AdminTone.bad => AdminColors.badTint,
      };
}

/// One raised surface, at one radius, with one shadow.
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 20),
    this.alert = false,
    this.width,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Tints the whole card. For a number that means something is wrong, not
  /// for a number that is merely large.
  final bool alert;

  final double? width;

  static const double radius = 14;

  /// Barely there. A dashboard is a page of cards, and a shadow heavy enough
  /// to notice on one of them is noise on twelve.
  static const List<BoxShadow> shadow = [
    BoxShadow(color: Color(0x0D0A1A3F), blurRadius: 16, offset: Offset(0, 5)),
  ];

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: padding,
        decoration: BoxDecoration(
          color: alert ? AdminTone.bad.tint : AdminColors.card,
          border: Border.all(
            color: alert ? const Color(0xFFF0C8CD) : AdminColors.line,
          ),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: shadow,
        ),
        child: child,
      );
}

/// The small capitalised label above a number or a table.
class AdminEyebrow extends StatelessWidget {
  const AdminEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
          color: AdminColors.inkMuted,
        ),
      );
}

/// A rounded tile with an icon in it, in one of the tones.
class AdminIconTile extends StatelessWidget {
  const AdminIconTile(
    this.icon, {
    super.key,
    this.tone = AdminTone.neutral,
    this.size = 34,
  });

  final IconData icon;
  final AdminTone tone;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tone.tint,
          borderRadius: BorderRadius.circular(size / 3.4),
        ),
        child: Icon(icon, size: size * 0.53, color: tone.ink),
      );
}

/// A card with a heading, and optionally something to do with it.
///
/// Named a panel rather than a section because [AdminSection] is already the
/// sidebar's idea of a section, and a screen imports both.
class AdminPanel extends StatelessWidget {
  const AdminPanel({
    super.key,
    required this.title,
    required this.child,
    this.footnote,
    this.trailing,
  });

  final String title;
  final Widget child;

  /// The caveat that belongs with the number, under it rather than in a
  /// tooltip nobody opens.
  final String? footnote;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) => AdminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: AdminEyebrow(title)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
            if (footnote != null) ...[
              const SizedBox(height: 14),
              Text(
                footnote!,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AdminColors.inkMuted,
                ),
              ),
            ],
          ],
        ),
      );
}

/// One measured number, with what it is and what it means underneath.
///
/// The semantics are the label and the value together, because "12" read on
/// its own says nothing.
class AdminStat extends StatelessWidget {
  const AdminStat({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.icon,
    this.tone = AdminTone.neutral,
    this.alert = false,
    this.width,
  });

  final String label;
  final String value;
  final String? note;
  final IconData? icon;

  /// Colours the icon tile and, when [alert], the value.
  final AdminTone tone;

  /// Tints the card. Reserved for a number that needs someone to look at it.
  final bool alert;

  final double? width;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        child: ExcludeSemantics(
          child: AdminCard(
            width: width,
            alert: alert,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: AdminEyebrow(label),
                      ),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 10),
                      AdminIconTile(icon!, tone: tone),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.bold,
                    // Tabular, so a column of numbers lines up and a changing
                    // one does not shuffle the digits beside it.
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: alert ? AdminColors.bad : AdminColors.ink,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    note!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AdminColors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

/// A short status word: a role, a verdict, a state.
class AdminPill extends StatelessWidget {
  const AdminPill(
    this.label, {
    super.key,
    this.tone = AdminTone.neutral,
    this.background,
    this.foreground,
  });

  final String label;
  final AdminTone tone;

  /// For pills that carry their own meaning — the three account roles are
  /// told apart by colour as well as by word.
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: background ?? tone.tint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: foreground ?? tone.ink,
          ),
        ),
      );
}

/// The hairline between rows of a table.
class AdminRowDivider extends StatelessWidget {
  const AdminRowDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFFEDF0F6),
      );
}
