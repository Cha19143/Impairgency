import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/places/journey_recorder.dart';
import 'package:impairgency/core/places/session_event.dart';

import '../core/places/fake_journey_store.dart';

/// Where the dashboard's journeys come from.
void main() {
  late FakeJourneyStore store;
  late AppSession session;

  SessionState user({bool history = true}) => SessionState(
        uid: 'u1',
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: Routes.onboardingFlow.toSet(),
        consent: {'history': history},
      );

  const home = Destination(
      id: 'home',
      label: 'Home',
      latitude: 14.79,
      longitude: 120.92,
      kind: DestinationKind.home);
  const found = Destination(
      id: 'search-123', label: 'Jollibee', latitude: 14.8, longitude: 120.9);

  final fix = LocationFix(
      latitude: 14.788, longitude: 120.92, accuracyMetres: 8, at: DateTime.now());

  setUp(() {
    store = FakeJourneyStore();
    session = AppSession(journeyStore: store);
  });

  test('choosing a place starts a journey; stopping publishes it', () async {
    session.update(user());
    await session.setDestination(home);
    final id = session.journeys.sessionId!;
    session.recordJourneyFix(fix);
    session.noticedObstacle('stairs');
    session.recordJourneyEvent(SessionEventKind.sosFired);
    await pumpEventQueue();

    await session.setDestination(null);
    final summary = store.published.single;
    expect(summary.sessionId, id);
    expect(summary.countOf(SessionEventKind.stairsDetected), 1);
    expect(summary.countOf(SessionEventKind.sosFired), 1);
    expect(summary.placeLabels, ['Home']);
  });

  test('arriving ends it, and a search result is not named', () async {
    session.update(user());
    await session.setDestination(found);
    await session.arrived();
    expect(store.published.single.placeLabels, isEmpty);
    expect(session.destination, found, reason: 'the screen still shows it');
  });

  test('with history off, nothing is written', () async {
    session.update(user(history: false));
    await session.setDestination(home);
    session.recordJourneyFix(fix);
    await session.setDestination(null);
    expect(store.events, isEmpty);
    expect(store.published, isEmpty);
  });

  test('signing out ends the journey', () async {
    session.update(user());
    await session.setDestination(home);
    await session.journeys.end(); // what signOut() does first
    expect(store.published, hasLength(1));
  });

  testWidgets('ten minutes away ends it; coming back sooner does not',
      (tester) async {
    session.update(user());
    await session.setDestination(home);

    session.setForeground(false);
    await tester.pump(const Duration(minutes: 5));
    session.setForeground(true);
    await tester.pump(kJourneyIdleEnd);
    expect(store.published, isEmpty);

    session.setForeground(false);
    await tester.pump(kJourneyIdleEnd);
    expect(store.published, hasLength(1));
  });
}
