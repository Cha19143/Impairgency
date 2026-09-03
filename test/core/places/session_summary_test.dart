import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/places/journey.dart';
import 'package:impairgency/core/places/session_event.dart';
import 'package:impairgency/core/places/session_summary.dart';
import 'package:impairgency/core/places/timeline.dart';

final start = DateTime.utc(2026, 9, 3, 8, 0);

LocationFix fix(int second, {double offset = 0, double accuracy = 10}) =>
    LocationFix(
      latitude: 14.7942 + offset,
      longitude: 120.9214,
      accuracyMetres: accuracy,
      at: start.add(Duration(seconds: second)),
    );

SessionEvent event(SessionEventKind kind, int second, {String id = 'e'}) =>
    SessionEvent(
        id: id, sessionId: 's1', at: start.add(Duration(seconds: second)), kind: kind);

SessionSummary summaryOf({
  String userId = 'vi-1',
  String sessionId = 's1',
  List<SessionEvent> events = const [],
  List<String> labels = const [],
  int accuracyMetres = 10,
  int steps = 61,
}) {
  final journey = journeyFrom(
    sessionId,
    List.generate(
      steps,
      (i) => fix(i * 10,
          offset: i * 0.0001, accuracy: accuracyMetres.toDouble()),
    ),
  );
  return summariseSession(buildTimeline(journey, events),
      userId: userId, placeLabels: labels);
}

void main() {
  group('what a summary carries', () {
    test('durations, distances and counts', () {
      final summary = summaryOf(events: [
        event(SessionEventKind.obstacleDetected, 30),
        event(SessionEventKind.obstacleDetected, 60, id: 'b'),
        event(SessionEventKind.stairsDetected, 90, id: 'c'),
      ]);

      expect(summary.duration, const Duration(minutes: 10));
      expect(summary.metresTravelled, greaterThan(600));
      expect(summary.countOf(SessionEventKind.obstacleDetected), 2);
      expect(summary.countOf(SessionEventKind.stairsDetected), 1);
      expect(summary.countOf(SessionEventKind.sosFired), 0);
    });

    test('no coordinates, ever', () {
      // The whole reason summaries exist: an administrator gets counts, not a
      // map of where a blind person lives.
      final json = summaryOf(labels: const ['Home']).toJson();
      final flat = json.toString().toLowerCase();

      expect(json.keys, isNot(contains('lat')));
      expect(json.keys, isNot(contains('lng')));
      expect(flat, isNot(contains('14.79')));
      expect(flat, isNot(contains('120.92')));
    });

    test('only carries place names the user typed', () {
      final summary = summaryOf(labels: const ['Home', 'the clinic']);
      expect(summary.placeLabels, ['Home', 'the clinic']);
    });

    test('records the share of readings that were unusable', () {
      final clean = summaryOf();
      expect(clean.discardedFraction, 0);

      final noisy = summaryOf(accuracyMetres: 3000);
      expect(noisy.discardedFraction, 1.0);
    });

    test('flags an emergency', () {
      expect(summaryOf().hadEmergency, isFalse);
      expect(summaryOf(events: [event(SessionEventKind.sosFired, 30)]).hadEmergency,
          isTrue);
    });

    test('carries the concern count so a reviewer can triage', () {
      final summary = summaryOf(events: [
        event(SessionEventKind.sosCancelled, 30),
      ]);
      expect(summary.concernCount, greaterThan(0));
    });
  });

  group('the overview §1.3 asks for', () {
    test('counts users, sessions and emergencies', () {
      final overview = overviewOf([
        summaryOf(userId: 'a', sessionId: 's1'),
        summaryOf(userId: 'a', sessionId: 's2'),
        summaryOf(
            userId: 'b',
            sessionId: 's3',
            events: [event(SessionEventKind.sosFired, 30)]),
      ]);

      expect(overview.activeUsers, 2, reason: 'two distinct users');
      expect(overview.sessions, 3);
      expect(overview.sosIncidents, 1);
    });

    test('ranks the place names users typed, most common first', () {
      final overview = overviewOf([
        summaryOf(userId: 'a', labels: const ['Home', 'clinic']),
        summaryOf(userId: 'b', labels: const ['Home', 'market']),
        summaryOf(userId: 'c', labels: const ['Home']),
      ]);

      expect(overview.frequentPlaceLabels.first.label, 'Home');
      expect(overview.frequentPlaceLabels.first.count, 3);
      expect(overview.frequentPlaceLabels.map((e) => e.label),
          containsAll(['clinic', 'market']));
    });

    test('breaks ties by name, so the panel does not reshuffle itself', () {
      final overview = overviewOf([
        summaryOf(userId: 'a', labels: const ['zoo', 'aviary']),
      ]);
      expect(overview.frequentPlaceLabels.map((e) => e.label), ['aviary', 'zoo']);
    });

    test('ignores blank labels', () {
      final overview =
          overviewOf([summaryOf(userId: 'a', labels: const ['', '   ', 'Home'])]);
      expect(overview.frequentPlaceLabels, hasLength(1));
    });

    test('ranks detections by kind', () {
      final overview = overviewOf([
        summaryOf(userId: 'a', events: [
          event(SessionEventKind.obstacleDetected, 10),
          event(SessionEventKind.obstacleDetected, 20, id: 'b'),
          event(SessionEventKind.stairsDetected, 30, id: 'c'),
        ]),
      ]);

      expect(overview.detectionCounts.first.kind, 'obstacleDetected');
      expect(overview.detectionCounts.first.count, 2);
    });

    test('reports positioning quality rather than inventing an accuracy', () {
      final overview = overviewOf([
        summaryOf(userId: 'a'),
        summaryOf(userId: 'b', accuracyMetres: 3000),
        summaryOf(userId: 'c'),
      ]);
      expect(overview.medianDiscardedFraction, 0);
    });

    test('says out loud that counts are not accuracy', () {
      // §1.3 asks for detection performance. Performance means accuracy,
      // accuracy needs labelled ground truth, and nobody has labelled it.
      // Printing a made-up percentage would be worse than printing counts.
      expect(UsageOverview.detectionCaveat, contains('not accuracy'));
      expect(UsageOverview.detectionCaveat, contains('label'));
    });

    test('an empty period is zeroes, not a crash', () {
      final overview = overviewOf(const []);
      expect(overview.activeUsers, 0);
      expect(overview.sessions, 0);
      expect(overview.frequentPlaceLabels, isEmpty);
    });
  });
}
