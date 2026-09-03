import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/alerts/sos_alert.dart';

final now = DateTime.utc(2026, 9, 3, 12, 0);

SosEvent event({
  String id = 'e1',
  Duration age = Duration.zero,
  bool cancelled = false,
  String? location,
}) =>
    SosEvent(
      id: id,
      userId: 'vi-1',
      at: now.subtract(age),
      cancelled: cancelled,
      locationSummary: location,
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
}
