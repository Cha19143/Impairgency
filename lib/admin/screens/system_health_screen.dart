import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/admin/sos_record.dart';
import '../../core/location/location_policy.dart';
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
/// What *is* measured comes from the session summaries and the SOS records,
/// which are real.
class SystemHealthScreen extends StatelessWidget {
  const SystemHealthScreen({
    super.key,
    required this.overview,
    required this.sessionsNeedingAttention,
    this.sosEvents = const [],
    this.userNames = const {},
    this.onResolve,
    this.now,
    this.projectId = 'impairgency-capstone',
    this.openLink = _openInNewTab,
  });

  final UsageOverview overview;

  /// Sessions the review timeline flagged — the closest thing to an error rate
  /// this project can honestly report.
  final List<SessionSummary> sessionsNeedingAttention;

  /// Every SOS in the period, newest first.
  final List<SosRecord> sosEvents;

  /// Names for user ids, so a row says who. A uid is shown for anyone
  /// missing.
  final Map<String, String> userNames;

  /// Marks an active SOS as over. Null hides the button.
  final Future<void> Function(SosRecord record)? onResolve;

  /// The time rows are aged against. Null means now.
  final DateTime? now;

  final String projectId;

  final Future<void> Function(Uri uri) openLink;

  static Future<void> _openInNewTab(Uri uri) async {
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

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
        AdminPanel(
          title: 'Emergencies',
          footnote: 'Every SOS a signed-in phone sent in the last 30 days, '
              'including the ones cancelled in time. An SOS stays active '
              'until the user says they are okay or it is marked resolved '
              'here.',
          child: sosEvents.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No SOS in the last 30 days.',
                      style: TextStyle(
                          fontSize: 13.5, color: AdminColors.inkMuted)),
                )
              : Column(
                  children: [
                    for (final (i, record) in sosEvents.indexed) ...[
                      if (i > 0) const AdminRowDivider(),
                      _SosRow(
                        record: record,
                        name: userNames[record.userId],
                        now: now ?? DateTime.now(),
                        onResolve: onResolve,
                        openLink: openLink,
                      ),
                    ],
                  ],
                ),
        ),
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
                  'console.firebase.google.com/project/$projectId/crashlytics',
                  openLink: openLink),
              const SizedBox(height: 6),
              _ConsoleLink(
                  'console.firebase.google.com/project/$projectId/performance',
                  openLink: openLink),
            ],
          ),
        ),
      ],
    );
  }
}

/// A console address that opens in a new tab. Firebase asks the
/// administrator to sign in there if they are not already.
class _ConsoleLink extends StatelessWidget {
  const _ConsoleLink(this.url, {required this.openLink});

  final String url;
  final Future<void> Function(Uri uri) openLink;

  @override
  Widget build(BuildContext context) => Semantics(
        link: true,
        label: 'Open $url in a new tab',
        child: Material(
          color: AdminColors.field,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => openLink(Uri.parse('https://$url')),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AdminColors.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.open_in_new,
                      size: 15, color: AdminColors.inkMuted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      url,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        color: AdminColors.ink,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// One SOS: when, who, where, who was called, and whether it is over.
class _SosRow extends StatelessWidget {
  const _SosRow({
    required this.record,
    required this.name,
    required this.now,
    required this.onResolve,
    required this.openLink,
  });

  final SosRecord record;
  final String? name;
  final DateTime now;
  final Future<void> Function(SosRecord record)? onResolve;
  final Future<void> Function(Uri uri) openLink;

  @override
  Widget build(BuildContext context) {
    final at = record.at?.toLocal();
    final when = at == null
        ? 'Just now'
        : '${_date(at)} · ${describeAge(now.difference(at))}';
    final tone = switch (record.status) {
      SosStatus.active => AdminTone.bad,
      SosStatus.cancelled => AdminTone.neutral,
      SosStatus.resolved => AdminTone.good,
    };
    final map = record.mapLink;
    const muted = TextStyle(fontSize: 12.5, color: AdminColors.inkMuted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name ?? record.userId,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.ink)),
                const SizedBox(height: 2),
                Text(when, style: muted),
                if (record.locationSummary != null) ...[
                  const SizedBox(height: 2),
                  Text(record.locationSummary!, style: muted),
                ],
                if (record.contactName != null) ...[
                  const SizedBox(height: 2),
                  Text('Called ${record.contactName}', style: muted),
                ],
                if (map != null) ...[
                  const SizedBox(height: 4),
                  Semantics(
                    link: true,
                    child: InkWell(
                      onTap: () => openLink(map),
                      child: Text(
                        'Map: ${record.lat!.toStringAsFixed(5)}, '
                        '${record.lng!.toStringAsFixed(5)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AdminColors.ink,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          AdminPill(record.statusLabel, tone: tone),
          if (record.status == SosStatus.active && onResolve != null)
            OutlinedButton(
              onPressed: () => onResolve!(record),
              child: const Text('Mark resolved'),
            ),
        ],
      ),
    );
  }

  static String _date(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }
}
