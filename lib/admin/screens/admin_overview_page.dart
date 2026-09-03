import 'package:flutter/material.dart';

import '../../core/places/session_summary.dart';
import '../../data/admin_repository.dart';
import '../admin_theme.dart';
import 'admin_shell.dart';
import 'overview_screen.dart';

/// Loads §1.3's metrics and hands them to [OverviewScreen].
///
/// Split from the screen so the screen can be tested against fixed data, and so
/// an empty dashboard is visibly empty rather than quietly showing zeroes that
/// look like measurements.
class AdminOverviewPage extends StatefulWidget {
  const AdminOverviewPage({
    super.key,
    required this.repository,
    this.onSelect,
    this.onSignOut,
  });

  final AdminRepository repository;
  final void Function(AdminSection)? onSelect;
  final VoidCallback? onSignOut;

  @override
  State<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends State<AdminOverviewPage> {
  late Future<UsageOverview> _future = widget.repository.overview();

  void _reload() =>
      setState(() => _future = widget.repository.overview());

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      current: '/admin/overview',
      title: 'Overview',
      subtitle: 'Last 30 days',
      onSelect: widget.onSelect,
      onSignOut: widget.onSignOut,
      child: FutureBuilder<UsageOverview>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return _Message(
              title: 'Could not load the dashboard',
              detail: 'The database refused the read. This usually means the '
                  'signed-in account is not on the admin roster.',
              onRetry: _reload,
            );
          }
          final data = snapshot.data!;
          if (data.sessions == 0) {
            return _Message(
              title: 'No sessions yet',
              detail: 'Numbers appear here once someone has used the app with '
                  'history turned on. Nothing is estimated in the meantime.',
              onRetry: _reload,
            );
          }
          return OverviewScreen(overview: data);
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.detail, this.onRetry});

  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AdminColors.card,
          border: Border.all(color: AdminColors.line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.ink)),
            const SizedBox(height: 6),
            Text(detail,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.45, color: AdminColors.inkMuted)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      );
}
