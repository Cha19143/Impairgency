import 'package:flutter/material.dart';

import '../../core/places/session_summary.dart';
import '../admin_theme.dart';
import '../admin_ui.dart';

/// §1.4 — "Monitor application and AI performance. Track errors, crashes,
/// response times, and system status."
///
/// Split honestly into what this project can measure and what it cannot.
///
/// Crash and performance telemetry go to Crashlytics and Performance
/// Monitoring, and **reading them back requires a service account** — a server,
/// which means a billing account this project does not have. So they are linked
/// to rather than mirrored. Inventing a crash-free percentage here would be the
/// same defect as the `99.2%` the old dashboard hardcoded.
///
/// What *is* measured comes from the session summaries, which are real.
class SystemHealthScreen extends StatelessWidget {
  const SystemHealthScreen({
    super.key,
    required this.overview,
    required this.sessionsNeedingAttention,
    this.projectId = 'impairgency-capstone',
  });

  final UsageOverview overview;

  /// Sessions the review timeline flagged — the closest thing to an error rate
  /// this project can honestly report.
  final List<SessionSummary> sessionsNeedingAttention;

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final quality = overview.sessions == 0
        ? null
        : (1 - overview.medianDiscardedFraction) * 100;
    final flagged = sessionsNeedingAttention.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720
              ? 3
              : (constraints.maxWidth >= 460 ? 2 : 1);
          final w = (constraints.maxWidth - 14 * (columns - 1)) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              AdminStat(
                width: w,
                label: 'Positioning quality',
                value: quality == null ? '—' : '${quality.round()}%',
                note: 'median usable readings per session',
                icon: Icons.my_location_outlined,
                tone: quality == null
                    ? AdminTone.neutral
                    : (quality >= 80 ? AdminTone.good : AdminTone.warn),
              ),
              AdminStat(
                width: w,
                label: 'Sessions flagged',
                value: '$flagged',
                note: 'of ${overview.sessions} in this period',
                icon: Icons.flag_outlined,
                tone: flagged == 0 ? AdminTone.good : AdminTone.warn,
              ),
              AdminStat(
                width: w,
                label: 'Emergencies',
                value: '${overview.sosIncidents}',
                note: 'SOS sent',
                icon: Icons.emergency_outlined,
                tone: overview.sosIncidents == 0
                    ? AdminTone.good
                    : AdminTone.bad,
              ),
            ],
          );
        }),
        const SizedBox(height: 16),
        if (sessionsNeedingAttention.isNotEmpty)
          AdminPanel(
            title: 'Sessions worth reviewing',
            child: Column(
              children: [
                for (final (i, session)
                    in sessionsNeedingAttention.take(8).indexed) ...[
                  if (i > 0) const AdminRowDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(session.sessionId,
                              style: const TextStyle(
                                  fontSize: 13, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 10),
                        AdminPill(
                          '${session.concernCount} '
                          'concern${session.concernCount == 1 ? '' : 's'}',
                          tone: AdminTone.warn,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        AdminPanel(
          title: 'Crashes and response times',
          footnote:
              'Not mirrored here on purpose. Reading Crashlytics or Performance '
              'Monitoring back into a dashboard needs a service account, which '
              'needs a server, which needs a paid plan. Showing a made-up '
              'crash-free percentage would repeat exactly the defect this '
              'dashboard was built to fix.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The app reports crashes and traces to Firebase. They are read '
                'in the console:',
                style: TextStyle(
                    fontSize: 13, height: 1.45, color: AdminColors.ink),
              ),
              const SizedBox(height: 10),
              _ConsoleLink(
                  'console.firebase.google.com/project/$projectId/crashlytics'),
              const SizedBox(height: 6),
              _ConsoleLink(
                  'console.firebase.google.com/project/$projectId/performance'),
            ],
          ),
        ),
      ],
    );
  }
}

/// A console address, in a box that says "copy me" without pretending to be a
/// button that opens it — this dashboard cannot sign anyone into Firebase.
class _ConsoleLink extends StatelessWidget {
  const _ConsoleLink(this.url);

  final String url;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AdminColors.field,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AdminColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.open_in_new,
                size: 15, color: AdminColors.inkMuted),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                url,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                  color: AdminColors.ink,
                ),
              ),
            ),
          ],
        ),
      );
}
