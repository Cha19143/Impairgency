import 'dart:async';

import '../core/alerts/alert_presenter.dart';
import '../core/alerts/sos_alert.dart';

/// Raises a local alert when someone this guardian watches over fires an SOS.
///
/// This is the free replacement for a Cloud Function fan-out, and the trade-off
/// is honest: a server pushes to a phone that is asleep, whereas this only
/// works while the guardian app is running. On Android a foreground service
/// keeps it running; on iOS the OS will suspend it after a few minutes.
/// `docs/EMERGENCY_DELIVERY.md` states that plainly, and the production path
/// is written and waiting in `functions/index.js`.
///
/// Takes a stream rather than a Firestore query so the behaviour that matters -
/// what fires, what does not, and what fires only once - is testable without a
/// database.
class SosWatcher {
  SosWatcher({
    required this.presenter,
    required this.nameOf,
    this.now = DateTime.now,
  });

  final AlertPresenter presenter;

  /// Resolves a user id to a display name, so the notification can say who.
  final String? Function(String userId) nameOf;

  final DateTime Function() now;

  /// Ids already surfaced. Bounded below so a long-running guardian session
  /// cannot grow it without limit.
  final _alerted = <String>{};

  StreamSubscription<List<SosEvent>>? _subscription;

  Future<void> start(Stream<List<SosEvent>> events) async {
    await presenter.prepare();
    _subscription = events.listen(_handle);
  }

  Future<void> _handle(List<SosEvent> events) async {
    // Oldest first, so if two arrive together the newest alert is the last one
    // shown and therefore the one on top.
    final ordered = [...events]..sort((a, b) => a.at.compareTo(b.at));
    for (final event in ordered) {
      if (!shouldAlert(
        event: event,
        now: now(),
        alreadyAlerted: _alerted,
      )) {
        continue;
      }
      _alerted.add(event.id);
      await presenter.show(buildSosAlert(event, name: nameOf(event.userId)));
    }
    _prune();
  }

  /// Keeps the seen-set from growing forever. Well above any plausible number
  /// of emergencies in one session, and small enough to be free.
  void _prune() {
    const limit = 200;
    if (_alerted.length <= limit) return;
    final excess = _alerted.length - limit;
    _alerted.removeAll(_alerted.take(excess).toList());
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
