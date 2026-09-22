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

  /// Ids whose all-clear has been shown.
  final _okayed = <String>{};

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
      final at = now();
      if (shouldAlertOkay(event: event, now: at, alreadyTold: _okayed)) {
        _okayed.add(event.id);
        // Its emergency needs no alert of its own any more.
        _alerted.add(event.id);
        await presenter.show(
            buildOkAlert(event, name: nameOf(event.userId), now: at));
        continue;
      }
      if (!shouldAlert(
        event: event,
        now: at,
        alreadyAlerted: _alerted,
      )) {
        continue;
      }
      _alerted.add(event.id);
      await presenter.show(buildSosAlert(event, name: nameOf(event.userId)));
    }
    _prune(_alerted);
    _prune(_okayed);
  }

  /// Keeps the seen-set from growing forever. Well above any plausible number
  /// of emergencies in one session, and small enough to be free.
  static void _prune(Set<String> seen) {
    const limit = 200;
    if (seen.length <= limit) return;
    final excess = seen.length - limit;
    seen.removeAll(seen.take(excess).toList());
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
