import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/alerts/alert_presenter.dart';
import '../../core/alerts/sos_alert.dart';
import '../../core/guardian/watched_user.dart';
import '../../core/speech/speaker.dart';
import '../../data/guardian_repository.dart';
import '../sos_watcher.dart';
import 'guardian_home_screen.dart';

/// Keeps [GuardianHomeScreen] fed, and keeps the SOS watcher running.
///
/// The watcher is started here and nowhere else. Before this page existed,
/// `SosWatcher` was written, tested, documented as the free replacement for
/// server push - and never constructed, so no guardian was ever alerted.
class GuardianHomePage extends StatefulWidget {
  const GuardianHomePage({
    super.key,
    required this.guardianId,
    required this.repository,
    required this.presenter,
    required this.onEnterCode,
    required this.onSignOut,
    this.speaker = const SilentSpeaker(),
    this.reachabilityNote,
  });

  final String guardianId;
  final GuardianRepository repository;
  final AlertPresenter presenter;
  final VoidCallback onEnterCode;
  final VoidCallback onSignOut;
  final Speaker speaker;
  final String? reachabilityNote;

  @override
  State<GuardianHomePage> createState() => _GuardianHomePageState();
}

class _GuardianHomePageState extends State<GuardianHomePage> {
  StreamSubscription<List<WatchedUser>>? _sub;
  SosWatcher? _watcher;
  List<WatchedUser> _users = const [];
  bool _loading = true;
  final _names = <String, String>{};

  @override
  void initState() {
    super.initState();
    _sub = widget.repository.watch(widget.guardianId).listen(
      (users) {
        for (final u in users) {
          _names[u.uid] = u.displayName;
        }
        if (mounted) {
          setState(() {
            _users = users;
            _loading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
    _watcher = SosWatcher(
      presenter: widget.presenter,
      nameOf: (uid) => _names[uid],
    );
    unawaited(_watcher!.start(_feed()));
  }

  Stream<List<SosEvent>> _feed() =>
      widget.repository.sosFeed(widget.guardianId).handleError((_) {});

  @override
  void dispose() {
    _sub?.cancel();
    _watcher?.stop();
    super.dispose();
  }

  Future<bool> _call(CallTarget target) async {
    try {
      return await launchUrl(
        Uri(scheme: 'tel', path: target.number),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _openMap(WatchedUser user) async {
    final fix = user.fix;
    if (fix == null) return;
    try {
      await launchUrl(mapLinkFor(fix), mode: LaunchMode.externalApplication);
    } catch (_) {
      // The card already shows the sentence; a map that will not open is
      // not worth an error on top of it.
    }
  }

  @override
  Widget build(BuildContext context) => GuardianHomeScreen(
        users: _users,
        loading: _loading,
        speaker: widget.speaker,
        reachabilityNote: widget.reachabilityNote,
        onCall: _call,
        onOpenMap: _openMap,
        onEnterCode: widget.onEnterCode,
        onSignOut: widget.onSignOut,
      );
}
