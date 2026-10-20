import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/alerts/guardian_alert.dart';
import 'package:impairgency/core/clips/event_clip.dart';
import 'package:impairgency/core/guardian/obstacle_event.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/core/motion/fall_event.dart';
import 'package:impairgency/data/event_clip_repository.dart';
import 'package:impairgency/data/guardian_alert_repository.dart';
import 'package:impairgency/data/obstacle_history_repository.dart';

class _Clips implements EventClipSink {
  final saved = <ClosedClip>[];

  @override
  Future<void> save(String uid, ClosedClip clip) async {
    saved.add(clip);
  }
}

class _Obstacles implements ObstacleHistorySink {
  final rows = <ObstacleSighting>[];

  @override
  Future<void> record(String uid, ObstacleSighting sighting) async {
    rows.add(sighting);
  }
}

class _Falls implements FallHistorySink {
  int writes = 0;

  @override
  Future<void> record(
    String uid,
    FallMoment moment, {
    required String sessionId,
  }) async {
    writes++;
  }
}

class _Alerts implements GuardianAlertSink {
  final sent = <String>[];

  @override
  Future<void> send({
    required String uid,
    required String kind,
    required String message,
    required DateTime at,
    double? latitude,
    double? longitude,
  }) async {
    sent.add(kind);
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
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 8),
  }) async => LocationFix(
    latitude: 14.6,
    longitude: 120.98,
    accuracyMetres: 8,
    at: DateTime.utc(2026, 10, 20, 9),
  );

  @override
  Future<LocationFix?> lastKnownFix() async => null;
}

void main() {
  late _Clips clips;
  late _Obstacles obstacles;
  late _Falls falls;
  late _Alerts alerts;
  late AppSession session;

  final t0 = DateTime.utc(2026, 10, 20, 8);

  LocationFix fix(int minutes) => LocationFix(
    latitude: 14.6,
    longitude: 120.98,
    accuracyMetres: 8,
    at: t0.add(Duration(minutes: minutes)),
  );

  GrayFrame frameNow() => GrayFrame(
    at: DateTime.now(),
    width: 2,
    height: 2,
    pixels: Uint8List.fromList(const [4, 4, 4, 4]),
  );

  setUp(() {
    clips = _Clips();
    obstacles = _Obstacles();
    falls = _Falls();
    alerts = _Alerts();
    session = AppSession(
      eventClips: clips,
      obstacleHistory: obstacles,
      fallHistory: falls,
      guardianAlerts: alerts,
      location: _Here(),
    );
  });

  void signedIn({
    bool recording = true,
    bool activity = false,
    bool location = false,
    bool history = false,
  }) {
    session.update(
      SessionState(
        uid: 'u1',
        signedIn: true,
        consent: {
          'recording': recording,
          'activity': activity,
          'location': location,
          'history': history,
        },
      ),
    );
  }

  /// Lets a position land, then the tail timer, then the write.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(kClipTail + const Duration(milliseconds: 50));
    await tester.pump();
  }

  testWidgets('recording off keeps no buffer and writes nothing', (tester) async {
    signedIn(recording: false);
    session.offerClipFrame(frameNow());
    session.noteEventClip(kClipTriggerObstacle);
    await settle(tester);
    expect(clips.saved, isEmpty);

    signedIn();
    session.noteEventClip(kClipTriggerObstacle);
    await settle(tester);
    expect(clips.saved.single.frames, isEmpty);
  });

  testWidgets('an obstacle with recording on is a clip, and without activity it is not a history row', (tester) async {
    signedIn();
    session.offerClipFrame(frameNow());
    session.noteImportantObstacle(
      const ObstacleNotice(
        type: 'car',
        distanceMetres: 1.6,
        distanceApproximate: true,
      ),
    );
    await settle(tester);
    expect(clips.saved.single.triggers, [kClipTriggerObstacle]);
    expect(clips.saved.single.frames, hasLength(1));
    expect(clips.saved.single.latitude, 14.6);
    expect(obstacles.rows, isEmpty);
  });

  testWidgets('two triggers in the tail are one clip', (tester) async {
    signedIn();
    session.noteEventClip(kClipTriggerObstacle);
    session.noteEventClip(kClipTriggerFall);
    await settle(tester);
    expect(clips.saved, hasLength(1));
    expect(clips.saved.single.triggers, [
      kClipTriggerObstacle,
      kClipTriggerFall,
    ]);
  });

  testWidgets('the gap holds the next clip, and SOS does not wait', (tester) async {
    signedIn();
    session.noteEventClip(kClipTriggerObstacle);
    await settle(tester);
    session.noteEventClip(kClipTriggerFall);
    await settle(tester);
    expect(clips.saved, hasLength(1));

    session.noteEventClip(kClipTriggerSos);
    await settle(tester);
    expect(clips.saved, hasLength(2));
    expect(clips.saved.last.triggers, [kClipTriggerSos]);
    expect(clips.saved.last.frames, isEmpty);
  });

  testWidgets('a fall notes a clip when the pattern trips, and still writes history', (tester) async {
    signedIn(history: true, location: true);
    session.noteImportantFall();
    session.completeImportantFall(answered: true);
    await tester.pump();
    expect(falls.writes, 1);
    await settle(tester);
    expect(clips.saved.single.triggers, [kClipTriggerFall]);
  });

  testWidgets('a route deviation notes a clip beside the guardian alert', (tester) async {
    signedIn(location: true);
    session.recordRouteDeviation(fix(0), 40);
    await tester.pump();
    expect(alerts.sent, [kGuardianAlertRouteDeviation]);
    await settle(tester);
    expect(clips.saved.single.triggers, [kClipTriggerDeviation]);
    expect(clips.saved.single.latitude, 14.6);
  });

  test('an hour in one place notes a clip when the alert is sent', () async {
    signedIn(location: true);
    session.setForeground(true);
    for (var m = 0; m <= 60; m += 5) {
      session.noteStationaryReading(fix(m));
    }
    await pumpEventQueue();
    expect(alerts.sent, [kGuardianAlertStationary]);
    await Future<void>.delayed(kClipTail + const Duration(milliseconds: 50));
    expect(clips.saved.single.triggers, [kClipTriggerStationary]);
    expect(clips.saved.single.latitude, 14.6);
  });

  testWidgets('capture is off until recording is on', (tester) async {
    signedIn(recording: false);
    expect(session.captureClipFrames(), isFalse);
    signedIn();
    expect(session.captureClipFrames(), isTrue);
  });
}
