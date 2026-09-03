import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_policy.dart';
import 'package:impairgency/core/location/location_source.dart';

final DateTime now = DateTime.utc(2026, 9, 3, 12, 0);

LocationFix fixAgo(Duration age, {double accuracy = 12}) => LocationFix(
      latitude: 14.7942,
      longitude: 120.9214,
      accuracyMetres: accuracy,
      at: now.subtract(age),
    );

LocationOutcome resolve({
  LocationAvailability availability = LocationAvailability.ready,
  LocationFix? fix,
}) =>
    resolveLocationForSos(
        availability: availability, fix: fix, now: now);

void main() {
  group('a fresh fix', () {
    test('is sent and called the user location, plainly', () {
      final out = resolve(fix: fixAgo(const Duration(seconds: 20)));
      expect(out.trust, LocationTrust.fresh);
      expect(out.fix, isNotNull);
      expect(out.spoken, 'Your location was sent.');
    });

    test('says so when the reading is only a wide guess', () {
      // A 2 km "position" read out as a location is worse than no number.
      final out = resolve(fix: fixAgo(Duration.zero, accuracy: 2000));
      expect(out.trust, LocationTrust.fresh);
      expect(out.spoken, contains('accurate to about'));
      expect(out.fix, isNotNull, reason: 'still sent - it narrows a search');
    });
  });

  group('a stale fix', () {
    test('is still sent, because an old position narrows a search', () {
      final out = resolve(fix: fixAgo(const Duration(minutes: 20)));
      expect(out.trust, LocationTrust.lastKnown);
      expect(out.fix, isNotNull);
    });

    test('is never described as where the user is now', () {
      final out = resolve(fix: fixAgo(const Duration(minutes: 20)));
      expect(out.spoken, contains('last known'));
      expect(out.spoken, isNot(contains('Your location was sent.')));
    });

    test('always carries its age, in words', () {
      expect(resolve(fix: fixAgo(const Duration(minutes: 20))).spoken,
          contains('20 minutes ago'));
      expect(resolve(fix: fixAgo(const Duration(hours: 1))).spoken,
          contains('an hour ago'));
      expect(resolve(fix: fixAgo(const Duration(hours: 5))).spoken,
          contains('5 hours ago'));
      expect(resolve(fix: fixAgo(const Duration(days: 2))).spoken,
          contains('more than a day ago'));
    });

    test('the freshness boundary is inclusive and does not drift', () {
      expect(resolve(fix: fixAgo(kFreshEnough)).trust, LocationTrust.fresh);
      expect(
        resolve(fix: fixAgo(kFreshEnough + const Duration(seconds: 1))).trust,
        LocationTrust.lastKnown,
      );
    });
  });

  group('no fix at all', () {
    test('names which of the four problems it was', () {
      final spoken = {
        for (final a in LocationAvailability.values)
          a: resolve(availability: a, fix: null).spoken
      };
      // Four different causes with four different remedies. "Location
      // unavailable" would be true for all of them and useful for none.
      expect(spoken.values.toSet().length, LocationAvailability.values.length);
      expect(spoken[LocationAvailability.ready], contains('in time'));
      expect(spoken[LocationAvailability.denied], contains('sharing is off'));
      expect(spoken[LocationAvailability.deniedForever], contains('Settings'));
      expect(spoken[LocationAvailability.serviceDisabled],
          contains('turned off on this phone'));
    });

    test('never claims anything was sent', () {
      for (final a in LocationAvailability.values) {
        final out = resolve(availability: a, fix: null);
        expect(out.trust, LocationTrust.none);
        expect(out.hasSomethingToSend, isFalse);
        expect(out.spoken, contains('not sent'), reason: '$a');
      }
    });
  });

  group('permission guidance', () {
    test('only sends the user to Settings when asking again is pointless', () {
      expect(permissionGuidance(LocationAvailability.deniedForever),
          contains('Settings'));
      expect(permissionGuidance(LocationAvailability.denied),
          isNot(contains('Settings')));
    });

    test('a plain refusal explains what SOS can still do', () {
      final text = permissionGuidance(LocationAvailability.denied);
      expect(text, contains('sound the alarm'));
      expect(text, contains('call your contact'));
      expect(text, contains('cannot tell them where you are'));
    });

    test('every state has something to say', () {
      for (final a in LocationAvailability.values) {
        expect(permissionGuidance(a), isNotEmpty);
      }
    });
  });

  group('age wording', () {
    // Reached by the policy only above kFreshEnough, so the shorter phrasings
    // are asserted directly rather than left to ship untested.
    test('reads the way a person would say it', () {
      final cases = {
        Duration(seconds: 30): 'less than a minute ago',
        Duration(minutes: 1): 'a minute ago',
        Duration(minutes: 20): '20 minutes ago',
        Duration(minutes: 59): '59 minutes ago',
        Duration(hours: 1): 'an hour ago',
        Duration(hours: 23): '23 hours ago',
        Duration(days: 1): 'more than a day ago',
        Duration(days: 30): 'more than a day ago',
      };
      cases.forEach((duration, expected) {
        expect(describeAge(duration), expected, reason: '$duration');
      });
    });

    test('never says a bare number without a unit', () {
      for (var m = 0; m < 200; m += 7) {
        final text = describeAge(Duration(minutes: m));
        expect(text, anyOf(contains('minute'), contains('hour'),
            contains('day')), reason: '$m minutes -> $text');
      }
    });
  });

  group('the fix itself', () {
    test('serialises for Firestore with a UTC timestamp', () {
      final json = fixAgo(Duration.zero).toJson();
      expect(json['lat'], closeTo(14.7942, 1e-6));
      expect(json['lng'], closeTo(120.9214, 1e-6));
      expect(json['at'], endsWith('Z'));
    });

    test('reports its own age', () {
      expect(fixAgo(const Duration(minutes: 7)).ageAt(now).inMinutes, 7);
    });
  });
}
