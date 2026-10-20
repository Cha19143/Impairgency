import 'package:flutter/material.dart';

import '../../core/places/session_event.dart';
import '../../core/places/session_summary.dart';
import '../../core/speech/speaker.dart';
import '../admin_theme.dart';
import '../admin_ui.dart';
import 'analytics_screen.dart';  


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
    this.speaker = const SilentSpeaker(),
  });

  final UsageOverview overview;
  final String periodLabel;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('Open Analytics'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AnalyticsScreen(speaker: speaker)),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          // Cards fill the row rather than sitting at a fixed 208 px with dead
          // space beside them. Four across on a desktop, two on a tablet, one
          // on a phone.
          final columns = constraints.maxWidth >= 880
              ? 4
              : (constraints.maxWidth >= 460 ? 2 : 1);
          final cardWidth =
              (constraints.maxWidth - 14 * (columns - 1)) / columns;

          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              AdminStat(
                width: cardWidth,
                label: 'Active users',
                value: '${overview.activeUsers}',
                note: 'with a journey, or who shared a position, in this '
                    'period',
                icon: Icons.people_outline,
              ),
              AdminStat(
                width: cardWidth,
                label: 'Navigation sessions',
                value: '${overview.sessions}',
                note: 'started in this period',
                icon: Icons.route_outlined,
              ),
              AdminStat(
                width: cardWidth,
                label: 'SOS incidents',
                value: '${overview.sosIncidents}',
                // Counted from the SOS records: alerts that went out.
                // Countdowns cancelled in time are not counted here.
                note: overview.sosIncidents == 0
                    ? 'none in this period'
                    : 'sent - see System health',
                icon: Icons.emergency_outlined,
                tone: overview.sosIncidents > 0
                    ? AdminTone.bad
                    : AdminTone.good,
                alert: overview.sosIncidents > 0,
              ),
              AdminStat(
                width: cardWidth,
                label: 'Positioning quality',
                value: overview.sessions == 0
                    ? '—'
                    : '${((1 - overview.medianDiscardedFraction) * 100).round()}%',
                note: 'median usable readings',
                icon: Icons.my_location_outlined,
              ),
            ],
          );
        }),
        if (overview.sessions == 0) ...[
          const SizedBox(height: 18),
          const AdminPanel(
            title: 'Journeys',
            child: _Empty(kNoJourneysExplanation),
          ),
        ],
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 780;
          final panels = [
            AdminPanel(
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
            AdminPanel(
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
                    const SizedBox(height: 14),
                    panels.last,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: panels.first),
                    const SizedBox(width: 14),
                    Expanded(child: panels.last),
                  ],
                );
        }),
      ],
    );
  }
}

/// Why the journey numbers are blank, rather than a blank.
const String kNoJourneysExplanation =
    'No journeys recorded in this period. A journey is recorded when a user '
    'with history turned on follows directions to a place; users without '
    'history consent are not recorded.';

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
    SessionEventKind.destinationSet => 'Destinations set',
    SessionEventKind.routeDeviation => 'Route deviations',
    SessionEventKind.fallDetected => 'Falls',
    null => kindName,
  };
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
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(row.label,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AdminColors.ink),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : row.count / max,
                      minHeight: 9,
                      backgroundColor: const Color(0xFFE9EEF7),
                      valueColor:
                          const AlwaysStoppedAnimation(Color(0xFF1E3A8A)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text('${row.count}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.ink,
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
