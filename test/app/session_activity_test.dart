import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/guardian/activity.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/data/activity_repository.dart';

/// When the session tells the guardian what the app noticed.
class _Recorder implements ActivityRecorder {
  final rows = <(String, ActivityEvent)>[];
  @override
  Future<void> record(String uid, ActivityEvent event) async =>
      rows.add((uid, event));
}

void main() {
  late _Recorder recorder;
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
    recorder = _Recorder();
    session = AppSession(activity: recorder);
  });

  test('records with consent, as a headline', () async {
    session.update(user());
    session.recordActivity(
        ActivityKind.textRead, 'MEDICINE\nTake one daily');
    await pumpEventQueue();
    expect(recorder.rows, hasLength(1));
    expect(recorder.rows.single.$1, 'u1');
    expect(recorder.rows.single.$2.kind, ActivityKind.textRead);
    expect(recorder.rows.single.$2.detail, 'MEDICINE');
  });

  test('nothing without consent, and nothing signed out', () async {
    session.update(user(consent: const {'location': true}));
    session.recordActivity(ActivityKind.obstacle, 'chair');
    session.update(const SessionState(safetyAcknowledged: true));
    session.recordActivity(ActivityKind.obstacle, 'chair');
    await pumpEventQueue();
    expect(recorder.rows, isEmpty);
  });

  test('the same obstacle is one row, not one per frame', () async {
    session.update(user());
    session.recordActivity(ActivityKind.obstacle, 'chair');
    session.recordActivity(ActivityKind.obstacle, 'chair');
    session.recordActivity(ActivityKind.obstacle, 'person');
    await pumpEventQueue();
    expect(recorder.rows.map((r) => r.$2.detail), ['chair', 'person']);
  });

  test('an empty detail is not a row', () async {
    session.update(user());
    session.recordActivity(ActivityKind.textRead, '   \n ');
    await pumpEventQueue();
    expect(recorder.rows, isEmpty);
  });

  test('setting a destination is a journey row', () async {
    session.update(user());
    // Also records history, which needs Firebase and is caught inside;
    // the activity row is queued before that.
    unawaited(session.setDestination(const Destination(
        id: 'work', label: 'Work', latitude: 14.6, longitude: 121)));
    await pumpEventQueue();
    expect(recorder.rows.single.$2.kind, ActivityKind.journey);
    expect(recorder.rows.single.$2.detail, 'Work');
  });
}
