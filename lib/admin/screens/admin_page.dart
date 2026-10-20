import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/admin/admin_user.dart';
import '../../core/speech/screen_reading.dart';
import '../../core/speech/speaker.dart';
import '../admin_theme.dart';
import '../admin_ui.dart';
import 'admin_shell.dart';

/// How long a page may load before it is said to have failed.
///
/// A Firestore read with no connection can wait indefinitely, and a spinner
/// that never resolves is the one state this page promises not to show.
const Duration kAdminLoadTimeout = Duration(seconds: 15);

/// Loads something, then shows it inside the shell.
///
/// The failure states are spelled out rather than collapsed into a spinner
/// that never resolves: still loading, refused, unreachable, and genuinely
/// empty. The last one matters most — an empty dashboard has to look empty
/// rather than showing zeroes that read as measurements.
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
    this.speaker = const SilentSpeaker(),
    this.spoken = const [],
  });

  final String route;
  final String title;
  final String? subtitle;
  final Future<T> Function() load;

  /// Builds the page from what [load] returned. The third argument loads it
  /// again - for a page whose actions change what it shows.
  final Widget Function(BuildContext, T, Future<void> Function() reload)
      builder;
  final bool Function(T)? isEmpty;
  final String emptyTitle;
  final String emptyDetail;
  final void Function(AdminSection)? onSelect;
  final VoidCallback? onSignOut;

  /// Who is signed in. Shown in the sidebar, not used for anything else.
  final String? account;

  /// Reads the title, the sidebar, and [spoken] once when the page opens.
  final Speaker speaker;

  /// Labels and buttons on this page, besides the title and the sidebar.
  final List<String> spoken;

  @override
  State<AdminPage<T>> createState() => _AdminPageState<T>();
}

class _AdminPageState<T> extends State<AdminPage<T>> {
  late Future<T> _future = _load();
  bool _said = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _said) return;
      _said = true;
      widget.speaker.speakLines(screenReadingLines([
        widget.title,
        widget.subtitle,
        for (final section in adminSections) section.label,
        widget.account,
        if (widget.onSignOut != null) 'Sign out',
        ...widget.spoken,
      ]));
    });
  }

  /// The last page that loaded, kept on screen while the next one loads.
  /// Otherwise every edit would blank the table to a spinner and back, and
  /// lose the admin's place in it.
  T? _last;
  bool _hasLast = false;

  Future<T> _load() async {
    final data = await widget.load().timeout(kAdminLoadTimeout);
    _last = data;
    _hasLast = true;
    return data;
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // Shown by the builder below.
    }
  }

  /// A click on the section already open loads it again. Navigating to the
  /// current route is a no-op in go_router and there is no animation to show
  /// it happened, so the click used to do nothing visible at all - which is
  /// how a working sidebar gets reported as broken.
  void _select(AdminSection section) {
    if (section.route == widget.route) {
      unawaited(_reload());
      return;
    }
    widget.onSelect?.call(section);
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      current: widget.route,
      title: widget.title,
      subtitle: widget.subtitle,
      account: widget.account,
      onSelect: widget.onSelect == null ? null : _select,
      onSignOut: widget.onSignOut,
      child: FutureBuilder<T>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            if (_hasLast) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LinearProgressIndicator(minHeight: 2),
                  widget.builder(context, _last as T, _reload),
                ],
              );
            }
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            // Said by cause. Every failure used to read as a refusal, so a
            // dropped connection told an administrator they were not one.
            final error = snapshot.error!;
            return switch (describeFailure(error)) {
              AdminLoadFailure.refused => AdminMessage(
                  icon: Icons.lock_outline,
                  tone: AdminTone.bad,
                  title: 'Could not load this page',
                  detail: 'The database refused the read. This usually means '
                      'the signed-in account is not on the admin roster.',
                  onRetry: _reload,
                ),
              AdminLoadFailure.unreachable => AdminMessage(
                  icon: Icons.cloud_off_outlined,
                  tone: AdminTone.warn,
                  title: 'Could not reach the database',
                  detail: 'Check the connection and try again. Nothing is '
                      'shown until it has actually been read.',
                  onRetry: _reload,
                ),
              AdminLoadFailure.other => AdminMessage(
                  icon: Icons.error_outline,
                  tone: AdminTone.bad,
                  title: 'Could not load this page',
                  detail: 'The read failed: ${'$error'.split('\n').first}',
                  onRetry: _reload,
                ),
            };
          }
          final data = snapshot.data as T;
          if (widget.isEmpty?.call(data) ?? false) {
            return AdminMessage(
              title: widget.emptyTitle,
              detail: widget.emptyDetail,
              onRetry: _reload,
            );
          }
          return widget.builder(context, data, _reload);
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
