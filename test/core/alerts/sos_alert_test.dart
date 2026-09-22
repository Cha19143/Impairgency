import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/alerts/sos_alert.dart';

final now = DateTime.utc(2026, 9, 3, 12, 0);

SosEvent event({
  String id = 'e1',
  Duration age = Duration.zero,
  bool cancelled = false,
  String? location,
  Duration? resolvedAgo,
  String resolvedBy = 'user',
}) =>
    SosEvent(
      id: id,
      userId: 'vi-1',
      at: now.subtract(age),
      cancelled: cancelled,
      locationSummary: location,
      resolvedAt: resolvedAgo == null ? null : now.subtract(resolvedAgo),
      resolvedBy: resolvedAgo == null ? null : resolvedBy,
    );

void main() {
  group('deciding whether to interrupt someone', () {
    test('a fresh, live SOS does', () {
      expect(
        shouldAlert(event: event(), now: now, alreadyAlerted: const {}),
        isTrue,
      );
    });

    test('a cancelled one does not', () {
      // Cancelled during the arming countdown. Nothing happened.
      expect(
        shouldAlert(
            event: event(cancelled: true), now: now, alreadyAlerted: const {}),
        isFalse,
      );
    });

    test('one already shown does not fire twice', () {
      expect(
        shouldAlert(event: event(), now: now, alreadyAlerted: const {'e1'}),
        isFalse,
      );
    });

    test('history does not stampede when the listener attaches', () {
      // A Firestore listener replays everything matching its query on attach.
      // Without an age bound, every app launch would fire every past emergency
      // at once - and the one that matters would be buried in them.
      final old = [
        event(id: 'a', age: const Duration(hours: 2)),
        event(id: 'b', age: const Duration(days: 1)),
        event(id: 'c', age: const Duration(days: 30)),
      ];
      for (final e in old) {
        expect(shouldAlert(event: e, now: now, alreadyAlerted: const {}),
            isFalse, reason: e.id);
      }
    });

    test('the age bound is generous enough to survive a reboot mid-incident',
        () {
      expect(
        shouldAlert(
            event: event(age: const Duration(minutes: 14)),
            now: now,
            alreadyAlerted: const {}),
        isTrue,
      );
    });

    test('a clock skewed into the future still alerts', () {
      // Better to interrupt someone wrongly than to swallow an emergency
      // because a device clock is a few seconds ahead.
      expect(
        shouldAlert(
            event: event(age: const Duration(minutes: -5)),
            now: now,
            alreadyAlerted: const {}),
        isTrue,
      );
    });
  });

  group('what the guardian reads on a lock screen', () {
    test('names the person, because a guardian may watch several', () {
      final alert = buildSosAlert(event(), name: 'Bob Doe');
      expect(alert.title, 'Bob Doe needs help');
    });

    test('falls back to something meaningful when the name is missing', () {
      for (final name in [null, '', '   ']) {
        expect(buildSosAlert(event(), name: name).title,
            'Someone you watch over needs help');
      }
    });

    test('carries the location prose the SOS already produced', () {
      final alert = buildSosAlert(
        event(location: 'Your last known location, from 20 minutes ago, '
            'was sent.'),
        name: 'Bob',
      );
      expect(alert.body, contains('20 minutes ago'));
    });

    test('says plainly when there was no location', () {
      expect(buildSosAlert(event(), name: 'Bob').body,
          'No location was available.');
    });

    test('never implies a location it does not have', () {
      final alert = buildSosAlert(event(), name: 'Bob');
      expect(alert.body.toLowerCase(), isNot(contains('is at')));
      expect(alert.body.toLowerCase(), isNot(contains('located')));
    });

    test('carries the event id, so tapping it can open the right incident', () {
      expect(buildSosAlert(event(id: 'sos-77')).eventId, 'sos-77');
    });
  });

  group('"I am okay" after the call', () {
    // Not a cancellation - the call was made - so the guardian is told it is
    // over, rather than shown the emergency as if it were still going on.
    final over = event(age: const Duration(minutes: 5),
        resolvedAgo: const Duration(minutes: 1));

    test('a resolved SOS raises no emergency alert', () {
      expect(shouldAlert(event: over, now: now, alreadyAlerted: const {}),
          isFalse);
    });

    test('it raises the all-clear, once, while fresh', () {
      expect(shouldAlertOkay(event: over, now: now, alreadyTold: const {}),
          isTrue);
      expect(shouldAlertOkay(event: over, now: now, alreadyTold: const {'e1'}),
          isFalse);
      expect(
          shouldAlertOkay(
              event: event(
                  age: const Duration(hours: 2),
                  resolvedAgo: const Duration(hours: 1)),
              now: now,
              alreadyTold: const {}),
          isFalse);
      expect(shouldAlertOkay(event: event(), now: now, alreadyTold: const {}),
          isFalse, reason: 'not resolved');
    });

    test('names the person, when they called, and what to do if unsure', () {
      final alert = buildOkAlert(over, name: 'Ana', now: now);
      expect(alert.eventId, 'e1',
          reason: 'replaces the emergency on the lock screen');
      expect(alert.title, 'Ana says they are okay');
      expect(alert.body,
          'They called for help 5 minutes ago. Call them if you are not sure.');
    });

    test('an administrator marking it resolved is not the user saying so', () {
      final byAdmin = event(
          age: const Duration(minutes: 5),
          resolvedAgo: const Duration(minutes: 1),
          resolvedBy: 'admin-uid');
      final alert = buildOkAlert(byAdmin, name: 'Ana', now: now);
      expect(alert.title, "Ana's emergency was marked resolved");
      expect(alert.body, contains('An administrator marked it resolved'));
    });
  });
}
