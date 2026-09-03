import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/places/geo.dart';
import 'package:impairgency/core/places/place.dart';
import 'package:impairgency/core/places/stay.dart';

// Real coordinates in Bulacan, a few km apart, so the distances in these tests
// are the distances the app will actually see.
const home = (lat: 14.7942, lng: 120.9214);
const clinic = (lat: 14.7680, lng: 120.9464);

final day = DateTime.utc(2026, 9, 1, 6, 0);

LocationFix at((double lat, double lng) p, Duration offset,
        {double accuracy = 10}) =>
    LocationFix(
      latitude: p.$1,
      longitude: p.$2,
      accuracyMetres: accuracy,
      at: day.add(offset),
    );

/// A run of readings in one spot, one per minute.
List<LocationFix> lingering(
  ({double lat, double lng}) p, {
  required Duration from,
  required Duration minutes,
  double jitterMetres = 0,
}) =>
    List.generate(minutes.inMinutes + 1, (i) {
      // Jitter in latitude only; 1 degree of latitude is ~111,320 m.
      final drift = jitterMetres / 111320.0 * (i.isEven ? 1 : -1);
      return at((p.lat + drift, p.lng), from + Duration(minutes: i));
    });

void main() {
  group('distance', () {
    test('matches a known separation', () {
      // Home to clinic, measured: 3963.8 m.
      final d = metresBetween(home.lat, home.lng, clinic.lat, clinic.lng);
      expect(d, closeTo(3964, 5));
    });

    test('is zero for the same point and symmetric', () {
      expect(metresBetween(home.lat, home.lng, home.lat, home.lng),
          closeTo(0, 0.001));
      expect(
        metresBetween(home.lat, home.lng, clinic.lat, clinic.lng),
        closeTo(metresBetween(clinic.lat, clinic.lng, home.lat, home.lng), 0.001),
      );
    });

    test('handles a short hop at this latitude', () {
      // 0.0009 degrees of latitude is very close to 100 m.
      expect(metresBetween(home.lat, home.lng, home.lat + 0.0009, home.lng),
          closeTo(100, 2));
    });
  });

  group('stay detection — telling stopping apart from passing through', () {
    test('finds a long linger', () {
      final stays = detectStays(
          lingering(home, from: Duration.zero, minutes: const Duration(minutes: 40)));

      expect(stays, hasLength(1));
      expect(stays.single.duration, const Duration(minutes: 40));
      expect(stays.single.latitude, closeTo(home.lat, 0.001));
      expect(stays.single.fixCount, 41);
    });

    test('ignores a brief pause', () {
      // Waiting at a crossing. Not a place.
      final stays = detectStays(
          lingering(home, from: Duration.zero, minutes: const Duration(minutes: 4)));
      expect(stays, isEmpty);
    });

    test('ignores a straight-through walk', () {
      // Moving steadily: every fix is beyond the radius of the run's start.
      final walking = List.generate(
        30,
        (i) => at((home.lat + i * 0.0015, home.lng), Duration(minutes: i)),
      );
      expect(detectStays(walking), isEmpty);
    });

    test('finds two stays either side of a journey', () {
      final trace = [
        ...lingering(home, from: Duration.zero, minutes: const Duration(minutes: 30)),
        // 20 minutes of travel, well outside either radius.
        for (var i = 1; i < 20; i++)
          at((home.lat - i * 0.0013, home.lng + i * 0.0013),
              Duration(minutes: 30 + i)),
        ...lingering(clinic,
            from: const Duration(minutes: 50), minutes: const Duration(minutes: 45)),
      ];

      final stays = detectStays(trace);
      expect(stays, hasLength(2));
      expect(stays.first.latitude, closeTo(home.lat, 0.01));
      expect(stays.last.latitude, closeTo(clinic.lat, 0.01));
    });

    test('tolerates GPS drift inside a building', () {
      // Indoor readings wander. +/-40 m of jitter - an 80 m swing between
      // consecutive readings - must not split one stay in two.
      final stays = detectStays(lingering(home,
          from: Duration.zero,
          minutes: const Duration(minutes: 60),
          jitterMetres: 40));
      expect(stays, hasLength(1));
    });

    test('drift wider than the radius does split a stay, by design', () {
      // A known limit, asserted rather than hoped about. The algorithm measures
      // from the run's first reading, so a wander wider than kStayRadiusMetres
      // ends the run - and an unlucky first reading that is itself an outlier
      // clips the stay short. The fix, if it ever matters, is to measure from a
      // rolling centroid instead. It has not mattered: +/-40 m covers indoor
      // drift, and a genuine 200 m wander is someone walking.
      final stays = detectStays(lingering(home,
          from: Duration.zero,
          minutes: const Duration(minutes: 60),
          jitterMetres: 120));
      expect(stays.length, isNot(1));
    });

    test('does not emit the same stay repeatedly', () {
      // Restarting the scan inside a finished run would emit it again, one fix
      // shorter, forever.
      final stays = detectStays(
          lingering(home, from: Duration.zero, minutes: const Duration(hours: 3)));
      expect(stays, hasLength(1));
    });

    test('needs at least two readings', () {
      expect(detectStays([at((home.lat, home.lng), Duration.zero)]), isEmpty);
      expect(detectStays(const []), isEmpty);
    });

    test('sorts an out-of-order trace before reading it', () {
      final trace = lingering(home,
          from: Duration.zero, minutes: const Duration(minutes: 30))
        ..shuffle();
      expect(detectStays(trace), hasLength(1));
    });
  });

  group('clustering — somewhere you return to', () {
    Stay stay(({double lat, double lng}) p, int dayOffset) => Stay(
          latitude: p.lat,
          longitude: p.lng,
          arrived: day.add(Duration(days: dayOffset)),
          departed: day.add(Duration(days: dayOffset, hours: 1)),
          fixCount: 30,
        );

    test('merges repeat visits to one spot', () {
      final places = clusterIntoPlaces(
          [stay(home, 0), stay(home, 1), stay(home, 2)]);

      expect(places, hasLength(1));
      expect(places.single.visitCount, 3);
      expect(places.single.totalTime, const Duration(hours: 3));
    });

    test('keeps distinct spots apart', () {
      final places =
          clusterIntoPlaces([stay(home, 0), stay(clinic, 0), stay(home, 1)]);

      expect(places, hasLength(2));
      expect(places.first.visitCount, 2, reason: 'most visited comes first');
      expect(places.last.visitCount, 1);
    });

    test('merges spots just inside the radius', () {
      // 50 m apart: the same building's two entrances.
      final nearby = (lat: home.lat + 0.00045, lng: home.lng);
      expect(clusterIntoPlaces([stay(home, 0), stay(nearby, 1)]), hasLength(1));
    });

    test('does not merge spots outside it', () {
      // 300 m apart: the house and the shop up the road.
      final farther = (lat: home.lat + 0.0027, lng: home.lng);
      expect(clusterIntoPlaces([stay(home, 0), stay(farther, 1)]), hasLength(2));
    });

    test('does not chain a row of stays into one long place', () {
      // Single-linkage clustering would swallow this whole street as one place.
      // Centroid linkage stops it.
      final row = [
        for (var i = 0; i < 6; i++)
          stay((lat: home.lat + i * 0.0008, lng: home.lng), i),
      ];
      final places = clusterIntoPlaces(row);
      expect(places.length, greaterThan(1),
          reason: '400 m of street is not one place');
    });

    test('is not sensitive to the order stays arrive in', () {
      final stays = [stay(home, 0), stay(clinic, 1), stay(home, 2), stay(clinic, 3)];
      final forward = clusterIntoPlaces(stays);
      final backward = clusterIntoPlaces(stays.reversed.toList());

      expect(forward.length, backward.length);
      expect(forward.map((p) => p.visitCount), backward.map((p) => p.visitCount));
    });

    test('orders visits within a place oldest first', () {
      final places = clusterIntoPlaces([stay(home, 5), stay(home, 1), stay(home, 3)]);
      final arrivals = places.single.visits.map((v) => v.arrived).toList();
      expect(arrivals, orderedEquals([...arrivals]..sort()));
    });

    test('one visit is not a frequency', () {
      // §1.3 asks for frequently visited locations.
      final places =
          clusterIntoPlaces([stay(home, 0), stay(home, 1), stay(clinic, 0)]);
      final frequent = frequentPlaces(places);

      expect(frequent, hasLength(1));
      expect(frequent.single.visitCount, 2);
    });

    test('never invents a name', () {
      // Calling somewhere "Home" because someone sleeps there is an inference
      // about their life, not their location. The user names it or nobody does.
      final places = clusterIntoPlaces([stay(home, 0), stay(home, 1)]);
      expect(places.single.label, isNull);
      expect(places.single.copyWith(label: 'Home').label, 'Home');
    });

    test('handles no stays at all', () {
      expect(clusterIntoPlaces(const []), isEmpty);
      expect(frequentPlaces(const []), isEmpty);
    });
  });
}
