import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/guardian/obstacle_event.dart';
import 'package:impairgency/core/location/location_fix.dart';

void main() {
  final at = DateTime(2026, 10, 20, 16);

  ObstacleNotice car() => const ObstacleNotice(
        type: 'car',
        distanceMetres: 1.5,
        distanceApproximate: true,
      );

  test('the same type waits eight seconds, a different type does not', () {
    final throttle = ObstacleThrottle();
    final first = keepImportantObstacle(
      throttle: throttle,
      notice: car(),
      at: at,
    );
    final again = keepImportantObstacle(
      throttle: throttle,
      notice: car(),
      at: at.add(const Duration(seconds: 7)),
    );
    final person = keepImportantObstacle(
      throttle: throttle,
      notice: const ObstacleNotice(
        type: 'person',
        distanceMetres: 2,
        distanceApproximate: true,
      ),
      at: at.add(const Duration(seconds: 1)),
    );
    final later = keepImportantObstacle(
      throttle: throttle,
      notice: car(),
      at: at.add(const Duration(seconds: 8)),
    );

    expect(first!.type, 'car');
    expect(again, isNull);
    expect(person!.type, 'person');
    expect(later, isNotNull);
  });

  test('a position is kept with the row', () {
    final sighting = keepImportantObstacle(
      throttle: ObstacleThrottle(),
      notice: car(),
      at: at,
      fix: LocationFix(
        latitude: 14.84,
        longitude: 120.81,
        accuracyMetres: 8,
        at: at,
      ),
    );
    expect(sighting!.latitude, 14.84);
    expect(sighting.longitude, 120.81);
    expect(sighting.toJson()['distanceApproximate'], isTrue);
    expect(obstacleDistanceText(sighting), 'About 2 metres');
    expect(obstacleLocationText(sighting), '14.84000, 120.81000');
  });

  test('thirty days is the window the list and the cleanup share', () {
    final now = DateTime(2026, 10, 20, 12);
    expect(
      obstacleRangeStart(ObstacleDateFilter.last30Days, now),
      now.subtract(kObstacleRetention),
    );
    expect(kObstacleRetention, const Duration(days: 30));
    expect(kObstacleCooldown, const Duration(seconds: 8));
  });
}
