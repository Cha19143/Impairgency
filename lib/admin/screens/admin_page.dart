import 'package:flutter/material.dart';

import '../admin_theme.dart';
import '../admin_ui.dart';
import 'admin_shell.dart';

/// Loads something, then shows it inside the shell.
///
/// The three failure states are spelled out rather than collapsed into a
/// spinner that never resolves: still loading, refused, and genuinely empty.
/// The last one matters most — an empty dashboard has to look empty rather
/// than showing zeroes that read as measurements.
class AdminPage<T> extends StatefulWidget {
  const AdminPage({
    super.key,
    required this.route,
    required this.title,
    required this.load,
    required this.builder,
    this.subtitle,
    this.isEmpty,
    this.emptyTitle = 'Nothing here yet',
    this.emptyDetail =
        'Numbers appear once the app has been used with history turned on. '
        'Nothing is estimated in the meantime.',
    this.onSelect,
    this.onSignOut,
    this.account,
  });

  final String route;
  final String title;
  final String? subtitle;
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  final bool Function(T)? isEmpty;
  final String emptyTitle;
  final String emptyDetail;
  final void Function(AdminSection)? onSelect;
  final VoidCallback? onSignOut;

  /// Who is signed in. Shown in the sidebar, not used for anything else.
  final String? account;

  @override
  State<AdminPage<T>> createState() => _AdminPageState<T>();
}

class _AdminPageState<T> extends State<AdminPage<T>> {
  late Future<T> _future = widget.load();

  void _reload() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      current: widget.route,
      title: widget.title,
      subtitle: widget.subtitle,
      account: widget.account,
      onSelect: widget.onSelect,
      onSignOut: widget.onSignOut,
      child: FutureBuilder<T>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return AdminMessage(
              icon: Icons.lock_outline,
              tone: AdminTone.bad,
              title: 'Could not load this page',
              detail: 'The database refused the read. This usually means the '
                  'signed-in account is not on the admin roster.',
              onRetry: _reload,
            );
          }
          final data = snapshot.data as T;
          if (widget.isEmpty?.call(data) ?? false) {
            return AdminMessage(
              title: widget.emptyTitle,
              detail: widget.emptyDetail,
              onRetry: _reload,
            );
          }
          return widget.builder(context, data);
        },
      ),
    );
  }
}

class AdminMessage extends StatelessWidget {
  const AdminMessage({
    super.key,
    required this.title,
    required this.detail,
    this.onRetry,
    this.icon = Icons.inbox_outlined,
    this.tone = AdminTone.neutral,
  });

  final String title;
  final String detail;
  final VoidCallback? onRetry;

  /// An empty page and a refused read are different things, and the icon is
  /// the first thing read.
  final IconData icon;
  final AdminTone tone;

  @override
  Widget build(BuildContext context) => AdminCard(
        padding: const EdgeInsets.all(28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminIconTile(icon, tone: tone, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 17,
                          height: 1.3,
                          fontWeight: FontWeight.bold,
                          color: AdminColors.ink)),
                  const SizedBox(height: 6),
                  Text(detail,
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: AdminColors.inkMuted)),
                  if (onRetry != null) ...[
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: onRetry,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminColors.ink,
                        side: const BorderSide(color: AdminColors.line),
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}
