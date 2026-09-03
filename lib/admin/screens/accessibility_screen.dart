import 'package:flutter/material.dart';

import '../../app/theme.dart' show kContrastPairs;
import '../../core/a11y/contrast.dart';
import '../admin_theme.dart';
import '../admin_ui.dart';

/// §1.4's button, renamed to what it can actually show.
///
/// `ui.pdf` called this "Accessibility Audits" and defined it nowhere. A button
/// that audits nothing is worse than no button, so it shows the one
/// accessibility fact this project can state with certainty: the measured
/// contrast of every colour pair the app renders.
///
/// The numbers are computed live from `kContrastPairs` — the same constant the
/// app paints with and the test suite asserts against. There is no report file
/// to go stale: if someone changes a colour, this page changes with it, and
/// `test/core/contrast_test.dart` fails.
class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rows = kContrastPairs.entries
        .map((e) => (
              name: e.key,
              foreground: e.value.$1,
              background: e.value.$2,
              ratio: contrastRatio(e.value.$1, e.value.$2),
            ))
        .toList()
      ..sort((a, b) => a.ratio.compareTo(b.ratio));

    final failing = rows.where((r) => r.ratio < kAaNormalText).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: failing == 0
                ? AdminTone.good.tint
                : AdminTone.bad.tint,
            border: Border.all(
                color: failing == 0
                    ? const Color(0xFFB4DCC4)
                    : const Color(0xFFF0C8CD)),
            borderRadius: BorderRadius.circular(AdminCard.radius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminIconTile(
                failing == 0 ? Icons.verified_outlined : Icons.error_outline,
                tone: failing == 0 ? AdminTone.good : AdminTone.bad,
                size: 38,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failing == 0
                          ? 'Every rendered colour pair meets WCAG AA'
                          : '$failing colour pair${failing == 1 ? '' : 's'} '
                              'below WCAG AA',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.bold,
                        color:
                            failing == 0 ? AdminColors.good : AdminColors.bad,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Measured from the same constants the app paints with, '
                      'so this page cannot drift from what ships. '
                      'Requirements §4 asks for high contrast; this is the '
                      'evidence.',
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: AdminColors.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                _Row(
                  name: rows[i].name,
                  foreground: Color(rows[i].foreground),
                  background: Color(rows[i].background),
                  ratio: rows[i].ratio,
                  last: i == rows.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'AA is 4.5:1 for body text. AAA is 7:1. The three large action '
          'buttons are held to AAA, because the people aiming at them are the '
          'reason the app exists.',
          style:
              TextStyle(fontSize: 12.5, height: 1.5, color: AdminColors.inkMuted),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.name,
    required this.foreground,
    required this.background,
    required this.ratio,
    required this.last,
  });

  final String name;
  final Color foreground;
  final Color background;
  final double ratio;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final verdict = ratio >= kAaaNormalText
        ? ('AAA', AdminColors.good)
        : ratio >= kAaNormalText
            ? ('AA', AdminColors.good)
            : ratio >= kAaLargeText
                ? ('Large text only', AdminColors.warn)
                : ('Fails', AdminColors.bad);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFEDF0F6))),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        // Below this the four columns crush the name into two characters, so
        // the ratio and verdict move under it instead.
        final stacked = constraints.maxWidth < 460;

        // The sample is the point: a number nobody can see is easy to argue
        // with, and this is what the pair actually looks like.
        final sample = Container(
          width: 74,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AdminColors.line),
          ),
          child: Text('Sample',
              style: TextStyle(
                  color: foreground, fontSize: 11, fontWeight: FontWeight.bold)),
        );

        final label = Text(name,
            style: const TextStyle(fontSize: 13.5, color: AdminColors.ink));

        final measurement = Text(
          '${ratio.toStringAsFixed(1)}:1',
          textAlign: stacked ? TextAlign.left : TextAlign.right,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
            color: AdminColors.ink,
          ),
        );

        final grade = Text(
          verdict.$1,
          textAlign: stacked ? TextAlign.left : TextAlign.right,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: verdict.$2),
        );

        if (stacked) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sample,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    const SizedBox(height: 4),
                    Row(children: [
                      measurement,
                      const SizedBox(width: 10),
                      grade,
                    ]),
                  ],
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            sample,
            const SizedBox(width: 14),
            Expanded(child: label),
            SizedBox(width: 74, child: measurement),
            SizedBox(width: 120, child: grade),
          ],
        );
      }),
    );
  }
}
