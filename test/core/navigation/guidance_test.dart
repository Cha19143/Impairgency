import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/navigation/guidance.dart';

final t0 = DateTime.utc(2026, 9, 9, 8);

/// Roughly 111 metres per 0.001 degree of latitude.
const home = Destination(
    id: 'home', label: 'Home', latitude: 14.7900, longitude: 120.9200,
    kind: DestinationKind.home);

LocationFix at(double lat, double lng,
        {double? heading, double speed = 1.2, double accuracy = 8}) =>
    LocationFix(
      latitude: lat,
      longitude: lng,
      accuracyMetres: accuracy,
      at: t0,
      headingDegrees: heading,
      speedMetresPerSecond: speed,
    );

void main() {
  group('bearing and relative angle', () {
    test('north is 0, east is 90', () {
      expect(bearingDegrees(0, 0, 1, 0), closeTo(0, 0.01));
      expect(bearingDegrees(0, 0, 0, 1), closeTo(90, 0.01));
      expect(bearingDegrees(0, 0, -1, 0), closeTo(180, 0.01));
      expect(bearingDegrees(0, 0, 0, -1), closeTo(270, 0.01));
    });

    test('left is negative, right is positive, and it wraps', () {
      expect(relativeAngle(heading: 0, bearing: 90), 90);
      expect(relativeAngle(heading: 0, bearing: 270), -90);
      expect(relativeAngle(heading: 350, bearing: 10), 20);
      expect(relativeAngle(heading: 10, bearing: 350), -20);
      expect(relativeAngle(heading: 0, bearing: 180), 180);
    });
  });

  group('which way', () {
    Turn turn(double relative) =>
        turnFor(distanceMetres: 200, relative: relative);

    test('ahead is straight, and a little off is a bear', () {
      expect(turn(0), Turn.straight);
      expect(turn(15), Turn.straight);
      expect(turn(-35), Turn.slightLeft);
      expect(turn(35), Turn.slightRight);
    });

    test('a real turn is a turn, and behind is turn around', () {
      expect(turn(-90), Turn.left);
      expect(turn(90), Turn.right);
      expect(turn(-140), Turn.sharpLeft);
      expect(turn(140), Turn.sharpRight);
      expect(turn(175), Turn.turnAround);
      expect(turn(-175), Turn.turnAround);
    });

    test('no heading is said as unknown, never guessed', () {
      expect(turnFor(distanceMetres: 200, relative: null), Turn.unknown);
    });

    test('close enough is arrived, and a vague fix widens "close enough"', () {
      expect(turnFor(distanceMetres: 12, relative: 90), Turn.arrived);
      expect(turnFor(distanceMetres: 30, relative: 90, accuracyMetres: 50),
          Turn.arrived);
      expect(turnFor(distanceMetres: 30, relative: 90, accuracyMetres: 10),
          Turn.right);
    });
  });

  group('a heading is only a heading while moving', () {
    test('standing still, GPS course is noise', () {
      expect(at(14.79, 120.92, heading: 90, speed: 0.1).usableHeading, isNull);
      expect(at(14.79, 120.92, heading: 90, speed: 1.0).usableHeading, 90);
      expect(at(14.79, 120.92, heading: null).usableHeading, isNull);
      expect(at(14.79, 120.92, heading: -1).usableHeading, isNull);
    });
  });

  group('the sentences', () {
    test('name the turn, the place and a rounded distance', () {
      // 0.002 degrees south of home, walking north: home is straight ahead,
      // about 220 metres.
      final prompt = promptFor(here: at(14.788, 120.92), to: home, heading: 0);
      expect(prompt.turn, Turn.straight);
      expect(prompt.phrase, 'Keep going straight. Home is about 200 metres away.');
    });

    test('a turn, when home is off to the side', () {
      // Walking east with home due north: turn left.
      final prompt = promptFor(here: at(14.788, 120.92), to: home, heading: 90);
      expect(prompt.turn, Turn.left);
      expect(prompt.phrase, startsWith('Turn left.'));
    });

    test('arrival names the place and nothing else', () {
      final prompt = promptFor(here: at(14.79, 120.92), to: home, heading: 0);
      expect(prompt.phrase, 'You have arrived at Home.');
    });

    test('no heading asks for a few steps, and still says how far', () {
      final prompt = promptFor(here: at(14.788, 120.92), to: home);
      expect(prompt.phrase, contains('Walk a few steps'));
      expect(prompt.phrase, contains('about 200 metres'));
    });

    test('distances are rounded the way a person says them', () {
      expect(describeDistance(4), 'a few metres');
      expect(describeDistance(47), 'about 50 metres');
      expect(describeDistance(137), 'about 150 metres');
      expect(describeDistance(1240), 'about 1.2 kilometres');
      expect(describeDistance(12400), 'about 12 kilometres');
    });
  });

  group('the do-not-nag rule', () {
    NavigationPrompt p(Turn turn, double d) =>
        NavigationPrompt(turn: turn, distanceMetres: d, phrase: turn.name);

    test('the first prompt is always said', () {
      expect(
          shouldAnnounce(
              next: p(Turn.straight, 200), last: null, lastAt: null, now: t0),
          isTrue);
    });

    test('the same turn is not repeated every second', () {
      expect(
        shouldAnnounce(
            next: p(Turn.straight, 195),
            last: p(Turn.straight, 200),
            lastAt: t0,
            now: t0.add(const Duration(seconds: 2))),
        isFalse,
      );
    });

    test('but is after the timer, or after real progress', () {
      expect(
        shouldAnnounce(
            next: p(Turn.straight, 195),
            last: p(Turn.straight, 200),
            lastAt: t0,
            now: t0.add(kNavigationRepeat)),
        isTrue,
      );
      expect(
        shouldAnnounce(
            next: p(Turn.straight, 160),
            last: p(Turn.straight, 200),
            lastAt: t0,
            now: t0.add(const Duration(seconds: 3))),
        isTrue,
      );
    });

    test('a changed turn is said at once', () {
      expect(
        shouldAnnounce(
            next: p(Turn.left, 200),
            last: p(Turn.straight, 200),
            lastAt: t0,
            now: t0.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('flapping between neighbours waits for the timer', () {
      // "Straight. Slightly left. Straight. Slightly left." on a noisy
      // heading is a running commentary, not guidance.
      expect(
        shouldAnnounce(
            next: p(Turn.slightLeft, 200),
            last: p(Turn.straight, 200),
            lastAt: t0,
            now: t0.add(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('unknown is said once, arrived is said once', () {
      expect(
        shouldAnnounce(
            next: p(Turn.unknown, 200),
            last: p(Turn.unknown, 200),
            lastAt: t0,
            now: t0.add(const Duration(minutes: 5))),
        isFalse,
      );
      expect(
        shouldAnnounce(
            next: p(Turn.straight, 5),
            last: p(Turn.arrived, 5),
            lastAt: t0,
            now: t0.add(const Duration(minutes: 5))),
        isFalse,
      );
    });
  });

  group('a whole walk', () {
    test('says the turn, then the progress, then the arrival, and stops',
        () {
      var clock = t0;
      final session = NavigationSession(destination: home, now: () => clock);
      final said = <String>[];

      void step(LocationFix fix, {int seconds = 3}) {
        clock = clock.add(Duration(seconds: seconds));
        final prompt = session.update(fix);
        if (prompt != null) said.add(prompt.phrase);
      }

      // Start 330 m south, walking east: home is to the left.
      step(at(14.787, 120.92, heading: 90));
      // Turned north; now straight ahead.
      step(at(14.7872, 120.92, heading: 0));
      // A few noisy readings a few metres on, no new sentence.
      step(at(14.7873, 120.92, heading: 5));
      step(at(14.7874, 120.92, heading: 355));
      // Real progress.
      step(at(14.7885, 120.92, heading: 0));
      // Arrival.
      step(at(14.79, 120.92, heading: 0));
      // Past it, but arrived is final.
      step(at(14.7902, 120.92, heading: 0), seconds: 60);

      expect(said, [
        'Turn left. Home is about 350 metres away.',
        'Keep going straight. Home is about 300 metres away.',
        'Keep going straight. Home is about 150 metres away.',
        'You have arrived at Home.',
      ]);
      expect(session.arrived, isTrue);
    });
  });
}
