import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/places/journey.dart';

final start = DateTime.utc(2026, 9, 3, 8, 0);
const home = (lat: 14.7942, lng: 120.9214);

LocationFix fix({
  required int second,
  double latOffset = 0,
  double lngOffset = 0,
  double accuracy = 10,
}) =>
    LocationFix(
      latitude: home.lat + latOffset,
      longitude: home.lng + lngOffset,
      accuracyMetres: accuracy,
      at: start.add(Duration(seconds: second)),
    );

/// A steady walk: ~11 m every 10 seconds, about 1.1 m/s.
List<LocationFix> walk(int steps) => List.generate(
      steps,
      (i) => fix(second: i * 10, latOffset: i * 0.0001),
    );

void main() {
  group('a clean walk', () {
    test('keeps every reading and totals the distance', () {
      final journey = journeyFrom('s1', walk(11));

      expect(journey.path, hasLength(11));
      expect(journey.discarded, 0);
      // Ten steps of about 11 m.
      expect(journey.metresTravelled, closeTo(111, 5));
      expect(journey.duration, const Duration(seconds: 100));
    });

    test('reports when it started and ended', () {
      final journey = journeyFrom('s1', walk(5));
      expect(journey.startedAt, start);
      expect(journey.endedAt, start.add(const Duration(seconds: 40)));
    });

    test('sorts an out-of-order session', () {
      final journey = journeyFrom('s1', walk(8).reversed.toList());
      expect(journey.path.first.at, start);
      expect(journey.metresTravelled, closeTo(78, 5));
    });
  });

  group('throwing out what is not travel', () {
    test('drops a reading that teleports and comes back', () {
      // The classic artefact: one fix a kilometre away, one second later.
      final trace = [
        ...walk(5),
        fix(second: 41, latOffset: 0.01), // ~1.1 km in 1 second
        ...walk(5).map((f) => fix(second: 50 + f.at.second, latOffset: 0.0004)),
      ];
      final journey = journeyFrom('s1', trace);

      expect(journey.discarded, greaterThanOrEqualTo(1));
      // Without the filter this would read as over two kilometres.
      expect(journey.metresTravelled, lessThan(300));
    });

    test('drops readings too vague to place', () {
      // A 2 km accuracy is a cell-tower guess, not a position.
      final trace = [
        ...walk(5),
        fix(second: 60, latOffset: 0.002, accuracy: 2000),
        fix(second: 70, latOffset: 0.0005),
      ];
      final journey = journeyFrom('s1', trace);

      expect(journey.discarded, 1);
      expect(journey.path.any((f) => f.accuracyMetres > 200), isFalse);
    });

    test('surfaces how much it threw away', () {
      // A journey built from a handful of ninety readings deserves scepticism,
      // so the count is part of the result rather than hidden.
      final trace = [
        for (var i = 0; i < 10; i++)
          fix(second: i * 10, latOffset: i * 0.0001, accuracy: 900),
        ...walk(3),
      ];
      expect(journeyFrom('s1', trace).discarded, 10);
    });

    test('keeps a fast but plausible trip', () {
      // A jeepney at 60 km/h must not be mistaken for noise.
      final riding = List.generate(
        10,
        (i) => fix(second: i * 10, latOffset: i * 0.0015),
      );
      final journey = journeyFrom('s1', riding);

      expect(journey.discarded, 0);
      expect(journey.metresTravelled, greaterThan(1000));
    });

    test('handles two readings at the same instant', () {
      final trace = [
        fix(second: 0),
        fix(second: 0, latOffset: 0.00005),
        fix(second: 10, latOffset: 0.0001),
      ];
      final journey = journeyFrom('s1', trace);
      expect(journey.path.length, greaterThanOrEqualTo(2));
      expect(journey.metresTravelled.isFinite, isTrue);
    });

    test('drops a same-instant reading that also jumped', () {
      final trace = [
        fix(second: 0),
        fix(second: 0, latOffset: 0.01), // same moment, a kilometre away
      ];
      final journey = journeyFrom('s1', trace);
      expect(journey.path, hasLength(1));
      expect(journey.discarded, 1);
    });
  });

  group('nothing to show', () {
    test('an empty session is empty, not an error', () {
      final journey = journeyFrom('s1', const []);
      expect(journey.isEmpty, isTrue);
      expect(journey.metresTravelled, 0);
      expect(journey.duration, Duration.zero);
      expect(journey.startedAt, isNull);
    });

    test('a single reading is a point, not a path', () {
      final journey = journeyFrom('s1', [fix(second: 0)]);
      expect(journey.path, hasLength(1));
      expect(journey.metresTravelled, 0);
      expect(journey.duration, Duration.zero);
    });

    test('a session of only vague readings yields no path', () {
      final journey = journeyFrom('s1', [
        for (var i = 0; i < 5; i++) fix(second: i * 10, accuracy: 5000),
      ]);
      expect(journey.isEmpty, isTrue);
      expect(journey.discarded, 5);
    });
  });

  group('distance wording', () {
    test('reads the way a person would say it', () {
      expect(describeDistance(0), 'barely moved');
      expect(describeDistance(15), 'barely moved');
      expect(describeDistance(240), '240 metres');
      expect(describeDistance(247), '250 metres');
      expect(describeDistance(1500), '1.5 kilometres');
      expect(describeDistance(3963), '4 kilometres');
      expect(describeDistance(10000), '10 kilometres');
      expect(describeDistance(2050), '2.1 kilometres');
    });
  });
}
