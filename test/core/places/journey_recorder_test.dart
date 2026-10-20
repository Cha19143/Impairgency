import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/route_deviation.dart';
import 'package:impairgency/core/places/journey_recorder.dart';
import 'package:impairgency/core/places/session_event.dart';

import 'fake_journey_store.dart';

void main() {
  late FakeJourneyStore store;
  late DateTime clock;
  late JourneyRecorder recorder;

  LocationFix fix(double lat, {int seconds = 0}) => LocationFix(
        latitude: lat,
        longitude: 120.92,
        accuracyMetres: 8,
        at: DateTime.utc(2026, 9, 18, 10).add(Duration(seconds: seconds)),
      );

  setUp(() {
    store = FakeJourneyStore();
    clock = DateTime.utc(2026, 9, 18, 10);
    store.now = () => clock;
    recorder = JourneyRecorder(store: store, now: () => clock);
  });

  test('a journey is recorded under one id, and summarised when it ends',
      () async {
    // Nothing in the app wrote a summary, so the dashboard's Overview said
    // "No sessions yet" whatever anyone did.
    await recorder.start(
        uid: 'u1', consent: true, destination: 'Home', savedLabel: 'Home');
    final id = recorder.sessionId!;
    expect(id, startsWith('journey-'));

    await recorder.recordFix(fix(14.7880));
    clock = clock.add(const Duration(seconds: 30));
    await recorder.recordFix(fix(14.7885, seconds: 30));
    await recorder.recordEvent(SessionEventKind.guidanceGiven,
        detail: 'Turn left.');
    await recorder.recordEvent(SessionEventKind.obstacleDetected,
        detail: 'car', key: 'car');
    await recorder.end();

    expect(recorder.recording, isFalse);
    expect(store.fixes.map((f) => f.$2).toSet(), {id});
    expect(store.kindsIn(id), [
      SessionEventKind.destinationSet,
      SessionEventKind.guidanceGiven,
      SessionEventKind.obstacleDetected,
    ]);
    final summary = store.published.single;
    expect(summary.sessionId, id);
    expect(summary.userId, 'u1');
    expect(summary.countOf(SessionEventKind.obstacleDetected), 1);
    expect(summary.metresTravelled, greaterThan(50));
    expect(summary.placeLabels, ['Home']);
  });

  test('without history consent nothing is written', () async {
    await recorder.start(uid: 'u1', consent: false, destination: 'Home');
    await recorder.recordFix(fix(14.788));
    await recorder.recordEvent(SessionEventKind.guidanceGiven);
    await recorder.end();
    expect(recorder.recording, isFalse);
    expect(store.fixes, isEmpty);
    expect(store.events, isEmpty);
    expect(store.published, isEmpty);
  });

  test('a place found by search is not named in the summary', () async {
    await recorder.start(uid: 'u1', consent: true, destination: 'Jollibee');
    await recorder.end();
    expect(store.published.single.placeLabels, isEmpty);
    expect(store.events.single.$2.detail, 'Jollibee',
        reason: "the user's own record keeps it");
  });

  test('a fix is kept every 10 metres or 10 seconds, not every reading',
      () async {
    await recorder.start(uid: 'u1', consent: true, destination: 'Home');
    await recorder.recordFix(fix(14.78800));
    await recorder.recordFix(fix(14.78802)); // 2 m, at once
    await recorder.recordFix(fix(14.78812)); // 13 m
    clock = clock.add(const Duration(seconds: 11));
    await recorder.recordFix(fix(14.78812, seconds: 11)); // still, 11 s on
    expect(store.fixes, hasLength(3));
  });

  test('the same obstacle is recorded once a minute', () async {
    await recorder.start(uid: 'u1', consent: true, destination: 'Home');
    for (var i = 0; i < 5; i++) {
      await recorder.recordEvent(SessionEventKind.obstacleDetected,
          detail: 'car', key: 'car');
    }
    await recorder.recordEvent(SessionEventKind.obstacleDetected,
        detail: 'person', key: 'person');
    clock = clock.add(const Duration(minutes: 1));
    await recorder.recordEvent(SessionEventKind.obstacleDetected,
        detail: 'car', key: 'car');
    expect(
        store.events
            .where((e) => e.$2.kind == SessionEventKind.obstacleDetected)
            .map((e) => e.$2.detail),
        ['car', 'person', 'car']);
  });

  test('a new destination ends the last journey first', () async {
    await recorder.start(uid: 'u1', consent: true, destination: 'Home');
    final first = recorder.sessionId;
    clock = clock.add(const Duration(minutes: 1));
    await recorder.start(uid: 'u1', consent: true, destination: 'Work');
    expect(recorder.sessionId, isNot(first));
    expect(store.published.single.sessionId, first);
  });

  test('ending with no journey does nothing', () async {
    await recorder.end();
    expect(store.published, isEmpty);
  });

  test('a refused write never takes the journey down', () async {
    store.fails = true;
    await recorder.start(uid: 'u1', consent: true, destination: 'Home');
    await recorder.recordFix(fix(14.788));
    await recorder.end();
    expect(recorder.recording, isFalse);
  });

  test('outside a journey, events are not recorded', () async {
    await recorder.recordEvent(SessionEventKind.sosFired);
    await recorder.recordFix(fix(14.788));
    await recorder.recordRouteDeviation(fix(14.788), distanceMetres: 40);
    expect(store.events, isEmpty);
    expect(store.fixes, isEmpty);
    expect(store.deviations, isEmpty);
  });

  test('a route deviation keeps where and how far, for a later notice',
      () async {
    await recorder.start(uid: 'u1', consent: true, destination: 'Home');
    final at = fix(14.79, seconds: 12);
    await recorder.recordRouteDeviation(at, distanceMetres: 37.4);

    final saved = store.deviations.single;
    expect(saved.$1, 'u1');
    expect(saved.$2, recorder.sessionId);
    final fields = saved.$3.documentFields(sessionId: saved.$2);
    expect(fields['type'], RouteDeviation.type);
    expect(fields['kind'], SessionEventKind.routeDeviation.name);
    expect(fields['lat'], 14.79);
    expect(fields['lng'], 120.92);
    expect(fields['distanceMetres'], 37.4);
    expect(fields['detail'], '37 m off the route');
    expect(saved.$3.at, at.at);
    expect(store.kindsIn(recorder.sessionId!),
        contains(SessionEventKind.routeDeviation));
  });
}
