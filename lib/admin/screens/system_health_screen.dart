import 'package:flutter/material.dart';

import '../../core/places/session_summary.dart';
import '../admin_theme.dart';

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
          final w = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
            _Stat(
              width: w,
              label: 'Positioning quality',
              value: quality == null ? '—' : '${quality.round()}%',
              note: 'median usable readings per session',
              state: quality == null
                  ? _State.unknown
                  : (quality >= 80 ? _State.good : _State.warn),
            ),
            _Stat(
              width: w,
              label: 'Sessions flagged',
              value: '$flagged',
              note: 'of ${overview.sessions} in this period',
              state: flagged == 0 ? _State.good : _State.warn,
            ),
            _Stat(
              width: w,
              label: 'Emergencies',
              value: '${overview.sosIncidents}',
              note: 'SOS sent',
              state: overview.sosIncidents == 0 ? _State.good : _State.bad,
            ),
          ],
          );
        }),
        const SizedBox(height: 16),
        if (sessionsNeedingAttention.isNotEmpty)
          _Card(
            title: 'Sessions worth reviewing',
            child: Column(
              children: [
                for (final session in sessionsNeedingAttention.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(session.sessionId,
                              style: const TextStyle(
                                  fontSize: 13, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(
                          '${session.concernCount} '
                          'concern${session.concernCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                              fontSize: 12.5, color: AdminColors.warn),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _Card(
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
              SelectableText(
                'console.firebase.google.com/project/$projectId/crashlytics',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: AdminColors.ink),
              ),
              const SizedBox(height: 4),
              SelectableText(
                'console.firebase.google.com/project/$projectId/performance',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: AdminColors.ink),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _State { good, warn, bad, unknown }

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.state,
    required this.width,
    this.note,
  });

  final String label;
  final String value;
  final double width;
  final String? note;
  final _State state;

  @override
  Widget build(BuildContext context) {
    final colour = switch (state) {
      _State.good => AdminColors.good,
      _State.warn => AdminColors.warn,
      _State.bad => AdminColors.bad,
      _State.unknown => AdminColors.inkMuted,
    };

    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
          decoration: BoxDecoration(
            color: AdminColors.card,
            border: Border.all(color: AdminColors.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: colour, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(label.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.inkMuted,
                        )),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(value,
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1.05,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: AdminColors.ink,
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

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.footnote});

  final String title;
  final Widget child;
  final String? footnote;

  @override
  Widget build(BuildContext context) => Container(
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
                      fontSize: 11.5, height: 1.4, color: AdminColors.inkMuted)),
            ],
          ],
        ),
      );
}
