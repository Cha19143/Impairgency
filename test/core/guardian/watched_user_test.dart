import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/guardian/watched_user.dart';
import 'package:impairgency/core/location/location_fix.dart';

final now = DateTime.utc(2026, 9, 9, 12);

LocationFix fix({Duration age = Duration.zero, double accuracy = 15}) =>
    LocationFix(
        latitude: 14.79,
        longitude: 120.92,
        accuracyMetres: accuracy,
        at: now.subtract(age));

void main() {
  group('the Call button rings the right person, and says who', () {
    test('the user, when they gave a number', () {
      final target = callTargetFor(const WatchedUser(
        uid: 'u',
        name: 'Ana',
        phone: '+63 917 000 0000',
        contactName: 'Mum',
        contactNumber: '0918',
      ));
      expect(target!.number, '+639170000000');
      expect(target.label, 'Call Ana');
    });

    test('their emergency contact, when they did not - and says so', () {
      // A guardian who taps Call and reaches themselves has been misled.
      final target = callTargetFor(const WatchedUser(
        uid: 'u',
        name: 'Ana',
        contactName: 'Mum',
        contactNumber: '0918 000 0000',
      ));
      expect(target!.number, '09180000000');
      expect(target.label, contains("Ana's emergency contact"));
      expect(target.label, contains('Mum'));
    });

    test('nobody, when there is nobody', () {
      const user = WatchedUser(uid: 'u', name: 'Ana');
      expect(callTargetFor(user), isNull);
      expect(noCallTargetMessage(user), contains('nobody to call'));
    });
  });

  group('the location line is true when read alone', () {
    test('not sharing is said as not sharing, with where to change it', () {
      final line = describeWatchedLocation(
          const WatchedUser(uid: 'u', name: 'Ana'),
          now: now);
      expect(line, contains('not sharing'));
      expect(line, contains('What the app is using'));
    });

    test('sharing with nothing recorded yet is not "unavailable"', () {
      final line = describeWatchedLocation(
          const WatchedUser(uid: 'u', name: 'Ana', sharesLocation: true),
          now: now);
      expect(line, contains('none has been recorded yet'));
      expect(line.toLowerCase(), isNot(contains('unavailable')));
    });

    test('a fresh fix is "here now"', () {
      final line = describeWatchedLocation(
          WatchedUser(
              uid: 'u', name: 'Ana', sharesLocation: true, fix: fix()),
          now: now);
      expect(line, 'Ana is here now.');
    });

    test('a stale fix always carries its age', () {
      final line = describeWatchedLocation(
          WatchedUser(
              uid: 'u',
              name: 'Ana',
              sharesLocation: true,
              fix: fix(age: const Duration(minutes: 40))),
          now: now);
      expect(line, contains('last seen 40 minutes ago'));
      expect(line, isNot(contains('here now')));
    });

    test('a vague fix says how vague', () {
      final line = describeWatchedLocation(
          WatchedUser(
              uid: 'u',
              name: 'Ana',
              sharesLocation: true,
              fix: fix(accuracy: 1800)),
          now: now);
      expect(line, contains('accurate only to about 1800 metres'));
    });

    test('a user with no name is still someone', () {
      final line = describeWatchedLocation(const WatchedUser(uid: 'u'), now: now);
      expect(line, startsWith('Someone you watch over'));
    });
  });

  test('the map link carries the position and opens anywhere', () {
    final uri = mapLinkFor(fix());
    expect(uri.scheme, 'https');
    expect(uri.queryParameters['query'], '14.79,120.92');
  });

  group('the SOS line', () {
    test('names a recent emergency', () {
      expect(
        describeLastSos(
            WatchedUser(
                uid: 'u', lastSos: now.subtract(const Duration(minutes: 5))),
            now: now),
        'Called for help 5 minutes ago.',
      );
    });

    test('says when they said they are okay', () {
      expect(
        describeLastSos(
            WatchedUser(
                uid: 'u',
                lastSos: now.subtract(const Duration(minutes: 5)),
                lastSosResolvedAt: now.subtract(const Duration(minutes: 2)),
                lastSosResolvedByUser: true),
            now: now),
        'Called for help 5 minutes ago, then said they are okay 2 minutes '
            'ago.',
      );
      expect(
        describeLastSos(
            WatchedUser(
                uid: 'u',
                lastSos: now.subtract(const Duration(minutes: 5)),
                lastSosResolvedAt: now.subtract(const Duration(minutes: 2))),
            now: now),
        'Called for help 5 minutes ago. An administrator marked it resolved '
            '2 minutes ago.',
      );
    });

    test('is silent about one from days ago', () {
      expect(
        describeLastSos(
            WatchedUser(uid: 'u', lastSos: now.subtract(const Duration(days: 2))),
            now: now),
        isNull,
      );
      expect(describeLastSos(const WatchedUser(uid: 'u'), now: now), isNull);
    });
  });
}
