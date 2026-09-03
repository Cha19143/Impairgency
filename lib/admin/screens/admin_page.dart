import 'package:flutter/material.dart';

import '../admin_theme.dart';
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
  });

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
