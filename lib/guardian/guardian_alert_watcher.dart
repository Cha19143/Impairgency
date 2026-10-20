import 'dart:async';

import '../core/alerts/alert_presenter.dart';
import '../core/alerts/guardian_alert.dart';
import '../core/alerts/sos_alert.dart';

/// Raises a local notification when the user phone writes a guardian alert.
///
/// The document is already in Firestore. This only runs while the guardian
/// app is open. It does not start a service, and it does not touch SOS.
class GuardianAlertWatcher {
  GuardianAlertWatcher({
    required this.presenter,
    required this.nameOf,
    this.now = DateTime.now,
  });

  final AlertPresenter presenter;
  final String? Function(String userId) nameOf;
  final DateTime Function() now;

  final _shown = <String>{};
  StreamSubscription<List<GuardianAlert>>? _subscription;

  Future<void> start(Stream<List<GuardianAlert>> alerts) async {
    await presenter.prepare();
    _subscription = alerts.listen(_handle);
  }

  Future<void> _handle(List<GuardianAlert> alerts) async {
    final ordered = [...alerts]..sort((a, b) => a.at.compareTo(b.at));
    for (final alert in ordered) {
      if (!shouldShowGuardianAlert(
        alert: alert,
        now: now(),
        alreadyShown: _shown,
      )) {
        continue;
      }
      _shown.add(alert.id);
      final name = nameOf(alert.userId);
      await presenter.show(
        SosAlert(
          eventId: alert.id,
          title: guardianAlertSentence(alert, name),
          body: 'Open live location to see where they are.',
          payload: guardianAlertLivePayload(alert.userId),
        ),
      );
    }
    const limit = 200;
    if (_shown.length > limit) {
      _shown.removeAll(_shown.take(_shown.length - limit).toList());
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
