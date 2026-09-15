import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/osrm.dart';
import 'package:impairgency/core/navigation/route.dart';
import 'package:impairgency/core/navigation/route_follower.dart';
import 'package:impairgency/core/navigation/route_phrases.dart';

import 'map_fixtures.dart';

final start = DateTime(2026, 9, 15, 9);

LocationFix at(
  RoutePoint p, {
  double? heading,
  double speed = 1.2,
  double accuracy = 8,
  int seconds = 0,
}) =>
    LocationFix(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyMetres: accuracy,
      at: start.add(Duration(seconds: seconds)),
      headingDegrees: heading,
      speedMetresPerSecond: heading == null ? 0 : speed,
    );

void main() {
  late WalkingRoute route;
  late DateTime now;
  late RouteFollower follower;

  setUp(() {
    route = parseOsrmRoute(osrmClinicRoute());
    now = start;
    follower = RouteFollower(route: route, to: 'the clinic', now: () => now);
  });

  /// Walks [north] and [east] metres from [from], a reading every [every]
  /// metres and three seconds, facing [heading]; returns everything said.
  List<String> walk(RoutePoint from,
      {double north = 0,
      double east = 0,
      required double heading,
      double every = 4,
      int? startSecond}) {
    final said = <String>[];
    final total = (north.abs() + east.abs());
    var second = startSecond ?? 0;
    for (var done = 0.0; done <= total + 0.001; done += every) {
      final f = total == 0 ? 0.0 : done / total;
      final p = moved(from, north: north * f, east: east * f);
      now = start.add(Duration(seconds: second));
      final g = follower.update(at(p, heading: heading, seconds: second));
      if (g.say != null) said.add(g.say!);
      second += 3;
    }
    return said;
  }

  test('each turn is said ahead of it and at it, once each', () {
    final said = walk(a, east: 118, heading: 90);
    expect(said, [
      'Walk straight ahead along Rizal Street.',
      'In about 50 metres, turn left onto Mabini Street.',
      'Now, turn left onto Mabini Street.',
    ]);
    expect(follower.update(at(b, heading: 0)).status,
        startsWith('Next: turn right, in about'));
  });

  test('a turn close behind the last rides along with it, and is said again',
      () {
    walk(a, east: 118, heading: 90);
    final said = walk(b, north: 78, heading: 0, startSecond: 60);
    expect(said, [
      'In about 50 metres, turn right.',
      'Now, turn right, then turn left.',
    ]);
    final after = walk(c, east: 14, heading: 90, every: 3, startSecond: 120);
    expect(after, ['Now, turn left.']);
  });

  test('arriving is said once, with the side', () {
    walk(a, east: 118, heading: 90);
    walk(b, north: 78, heading: 0, startSecond: 60);
    walk(c, east: 14, heading: 90, every: 3, startSecond: 120);
    final said = walk(d, north: 60, heading: 0, startSecond: 140);
    expect(said, [
      'In about 50 metres, you will reach the clinic.',
      'You have arrived at the clinic. It is on your right.',
    ]);
    expect(follower.arrived, isTrue);
    expect(follower.update(at(e, heading: 0)).say, isNull);
  });

  test('a vague reading moves nothing and says nothing', () {
    follower.update(at(a, heading: 90));
    final vague = follower.update(at(moved(a, east: 110), accuracy: 80));
    expect(vague.say, isNull);
    expect(follower.along, closeTo(0, 1));
  });

  group('leaving the route', () {
    test('takes three readings over eight seconds', () {
      follower.update(at(a, heading: 90));
      final away = moved(a, east: 40, north: 45);
      expect(follower.update(at(away, seconds: 1)).offRoute, isFalse);
      expect(follower.update(at(away, seconds: 2)).offRoute, isFalse);
      expect(follower.update(at(away, seconds: 3)).offRoute, isFalse,
          reason: 'three readings, but only two seconds apart');
      expect(follower.update(at(away, seconds: 9)).offRoute, isTrue);
    });

    test('one wild reading is not leaving it', () {
      follower.update(at(a, heading: 90));
      final wild = moved(a, east: 40, north: 60);
      follower.update(at(wild, seconds: 1));
      follower.update(at(moved(a, east: 44), heading: 90, seconds: 4));
      follower.update(at(wild, seconds: 8));
      expect(follower.update(at(wild, seconds: 12)).offRoute, isFalse);
    });

    test('a vague position needs to be further off', () {
      follower.update(at(a, heading: 90));
      final away = moved(a, east: 40, north: 35);
      for (final s in [1, 5, 10]) {
        expect(follower.update(at(away, accuracy: 30, seconds: s)).offRoute,
            isFalse,
            reason: '35 m off, but the reading is only good to 30 m');
      }
    });
  });

  group('the start', () {
    test('away from the path, the way to it', () {
      final inside = moved(a, north: -35);
      expect(follower.update(at(inside)).say,
          startsWith('The route starts on the nearest path'));
      now = start.add(const Duration(seconds: 3));
      expect(
          follower.update(at(moved(inside, north: 4), heading: 0, seconds: 3)).say,
          'Keep going straight. The path is about 30 metres away.');
      now = start.add(const Duration(seconds: 20));
      final onIt =
          follower.update(at(moved(a, north: -5), heading: 0, seconds: 20));
      expect(onIt.say, 'Turn right, and walk along Rizal Street.');
    });

    test('with no heading yet, a few steps, and then whether it is the right way',
        () {
      expect(follower.update(at(a)).say,
          'Walk a few steps along Rizal Street, so I can tell which way you are facing.');
      expect(follower.update(at(moved(a, east: 4), heading: 88, seconds: 3)).say,
          kRightWayPhrase);
    });

    test('walking the wrong way is said, and not every few seconds', () {
      final midway = moved(a, east: 60);
      follower.update(at(midway, heading: 90));
      final said = <String>[];
      for (var i = 1; i <= 6; i++) {
        now = start.add(Duration(seconds: i * 3));
        final g = follower.update(
            at(moved(midway, east: -3.0 * i), heading: 270, seconds: i * 3));
        if (g.say != null) said.add(g.say!);
      }
      expect(said, [kWrongWayPhrase]);
    });

    test('joining partway along names the way being walked', () {
      expect(follower.update(at(moved(b, north: 30), heading: 0)).say,
          startsWith('Walk straight ahead along Mabini Street.'));
    });
  });

  test('a lost position is said once, after half a minute', () {
    follower.update(at(a, heading: 90));
    now = start.add(const Duration(seconds: 20));
    expect(follower.tick().say, isNull);
    now = start.add(const Duration(seconds: 31));
    expect(follower.tick().say, kLostPositionPhrase);
    now = start.add(const Duration(seconds: 50));
    expect(follower.tick().say, isNull);
  });
}
