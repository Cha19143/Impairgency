import 'package:flutter/material.dart';

import '../../core/places/session_event.dart';
import '../../core/places/session_summary.dart';
import '../admin_theme.dart';

/// §1.3's five metrics.
///
/// Takes its data rather than fetching it, so every number on it can be
/// asserted in a widget test — which matters here more than usual: the screen
/// this replaces hardcoded `15.4K`, `99.2%` and `14ms` and looked entirely
/// convincing.
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({
    super.key,
    required this.overview,
    this.periodLabel = 'Last 30 days',
  });

  final UsageOverview overview;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          // Cards fill the row rather than sitting at a fixed 208 px with dead
          // space beside them. Four across on a desktop, two on a tablet, one
          // on a phone.
          final columns = constraints.maxWidth >= 880
              ? 4
              : (constraints.maxWidth >= 460 ? 2 : 1);
          final cardWidth =
              (constraints.maxWidth - 12 * (columns - 1)) / columns;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Kpi(
                width: cardWidth,
                label: 'Active users',
                value: '${overview.activeUsers}',
                note: 'with a session in this period',
              ),
              _Kpi(
                width: cardWidth,
                label: 'Navigation sessions',
                value: '${overview.sessions}',
              ),
              _Kpi(
                width: cardWidth,
                label: 'SOS incidents',
                value: '${overview.sosIncidents}',
                alert: overview.sosIncidents > 0,
              ),
              _Kpi(
                width: cardWidth,
                label: 'Positioning quality',
                value: overview.sessions == 0
                    ? '—'
                    : '${((1 - overview.medianDiscardedFraction) * 100).round()}%',
                note: 'median usable readings',
              ),
            ],
          );
        }),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 780;
          final panels = [
            _Panel(
              title: 'Frequently visited places',
              // §1.3. Counted from names users typed themselves - the summaries
              // carry no coordinates at all.
              footnote: 'Names users chose. No location data is stored here.',
              child: overview.frequentPlaceLabels.isEmpty
                  ? const _Empty('No named places yet.')
                  : _Bars(
                      rows: overview.frequentPlaceLabels
                          .take(6)
                          .map((e) => (label: e.label, count: e.count))
                          .toList(),
                    ),
            ),
            _Panel(
              title: 'Detections',
              footnote: UsageOverview.detectionCaveat,
              child: overview.detectionCounts.isEmpty
                  ? const _Empty('Nothing detected yet.')
                  : _Bars(
                      rows: overview.detectionCounts
                          .take(6)
                          .map((e) => (label: _pretty(e.kind), count: e.count))
                          .toList(),
                    ),
            ),
          ];
          return stacked
              ? Column(
                  children: [
                    panels.first,
                    const SizedBox(height: 12),
                    panels.last,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: panels.first),
                    const SizedBox(width: 12),
                    Expanded(child: panels.last),
                  ],
                );
        }),
      ],
    );
  }
}

String _pretty(String kindName) {
  final kind = SessionEventKind.values
      .where((k) => k.name == kindName)
      .firstOrNull;
  return switch (kind) {
    SessionEventKind.obstacleDetected => 'Obstacles',
    SessionEventKind.stairsDetected => 'Stairs',
    SessionEventKind.textRead => 'Text read',
    SessionEventKind.guidanceGiven => 'Guidance given',
    SessionEventKind.sosArmed => 'SOS armed',
    SessionEventKind.sosFired => 'SOS sent',
    SessionEventKind.sosCancelled => 'SOS cancelled',
    SessionEventKind.placeLearned => 'Places recognised',
    null => kindName,
  };
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.width,
    this.note,
    this.alert = false,
  });

  final String label;
  final String value;
  final double width;
  final String? note;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
          decoration: BoxDecoration(
            color: alert ? const Color(0xFFFDF4F5) : AdminColors.card,
            border: Border.all(
                color: alert ? const Color(0xFFE8B4BA) : AdminColors.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.inkMuted,
                  )),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                    fontSize: 27,
                    height: 1.05,
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: alert ? AdminColors.bad : AdminColors.ink,
                  )),
              if (note != null) ...[
                const SizedBox(height: 3),
                Text(note!,
                    style: const TextStyle(
                        fontSize: 11.5, color: AdminColors.inkMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.footnote});

  final String title;
  final Widget child;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AdminColors.card,
        border: Border.all(color: AdminColors.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: AdminColors.inkMuted,
              )),
          const SizedBox(height: 12),
          child,
          if (footnote != null) ...[
            const SizedBox(height: 12),
            Text(footnote!,
                style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AdminColors.inkMuted)),
          ],
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.rows});

  final List<({String label, int count})> rows;

  @override
  Widget build(BuildContext context) {
    final max = rows.map((r) => r.count).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(row.label,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : row.count / max,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE4E9F2),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF1E3A8A)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text('${row.count}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AdminColors.inkMuted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      )),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: AdminColors.inkMuted)),
      );
}
