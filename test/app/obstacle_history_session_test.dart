import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/guardian/activity.dart';
import 'package:impairgency/core/guardian/obstacle_event.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/data/activity_repository.dart';
import 'package:impairgency/data/obstacle_history_repository.dart';

class _Activity implements ActivityRecorder {
  final rows = <ActivityEvent>[];

  @override
  Future<void> record(String uid, ActivityEvent event) async {
    rows.add(event);
  }
}

class _Obstacles implements ObstacleHistorySink {
  final rows = <ObstacleSighting>[];

  @override
  Future<void> record(String uid, ObstacleSighting sighting) async {
    rows.add(sighting);
  }
}

class _Here implements LocationSource {
  @override
  Future<LocationAvailability> availability() async =>
      LocationAvailability.ready;

  @override
  Future<LocationAvailability> requestPermission() async =>
      LocationAvailability.ready;

  @override
  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 8)}) async {
    return LocationFix(
      latitude: 14.84,
      longitude: 120.81,
      accuracyMetres: 6,
      at: DateTime(2026, 10, 20, 16),
    );
  }

  @override
  Future<LocationFix?> lastKnownFix() async => null;
}

void main() {
  late _Activity activity;
  late _Obstacles obstacles;
  late AppSession session;

  SessionState user({Map<String, bool> consent = const {'activity': true}}) =>
      SessionState(
        uid: 'u1',
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: Routes.onboardingFlow.toSet(),
        consent: consent,
      );

  setUp(() {
    activity = _Activity();
    obstacles = _Obstacles();
    session = AppSession(
      activity: activity,
      obstacleHistory: obstacles,
      location: _Here(),
    );
  });

  const notice = ObstacleNotice(
    type: 'car',
    distanceMetres: 1.6,
    distanceApproximate: true,
  );

  test('an urgent obstacle is stored with position, and the activity row stays',
      () async {
    session.update(user());
    session.noticedObstacle('car');
    session.noteImportantObstacle(notice);
    await pumpEventQueue();
    expect(activity.rows.single.detail, 'car');
    expect(obstacles.rows, hasLength(1));
    expect(obstacles.rows.single.type, 'car');
    expect(obstacles.rows.single.latitude, 14.84);
    expect(obstacles.rows.single.longitude, 120.81);
    expect(obstacles.rows.single.distanceMetres, 1.6);
    expect(obstacles.rows.single.distanceApproximate, isTrue);
  });

  test('activity consent off stores nothing', () async {
    session.update(user(consent: const {'location': true}));
    session.noteImportantObstacle(notice);
    await pumpEventQueue();
    expect(obstacles.rows, isEmpty);
  });

  test('the same type inside eight seconds is one row', () async {
    session.update(user());
    session.noteImportantObstacle(notice);
    session.noteImportantObstacle(notice);
    session.noteImportantObstacle(const ObstacleNotice(
      type: 'person',
      distanceMetres: 2,
      distanceApproximate: true,
    ));
    await pumpEventQueue();
    expect(obstacles.rows.map((r) => r.type), ['car', 'person']);
  });
}
