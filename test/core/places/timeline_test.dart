import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/places/journey.dart';
import 'package:impairgency/core/places/session_event.dart';
import 'package:impairgency/core/places/timeline.dart';

final start = DateTime.utc(2026, 9, 3, 8, 0);

LocationFix fix(int second, {double offset = 0, double accuracy = 10}) =>
    LocationFix(
      latitude: 14.7942 + offset,
      longitude: 120.9214,
      accuracyMetres: accuracy,
      at: start.add(Duration(seconds: second)),
    );

SessionEvent event(
  SessionEventKind kind, {
  required int second,
  String? detail,
  String id = 'e',
}) =>
    SessionEvent(
      id: id,
      sessionId: 's1',
      at: start.add(Duration(seconds: second)),
      kind: kind,
      detail: detail,
    );

/// A ten-minute walk of about 700 m.
Journey walk({int minutes = 10}) => journeyFrom(
      's1',
      List.generate(
        minutes * 6 + 1,
        (i) => fix(i * 10, offset: i * 0.0001),
      ),
    );

void main() {
  group('the timeline itself', () {
    test('stamps events against the start of the session', () {
      final timeline = buildTimeline(walk(), [
        event(SessionEventKind.obstacleDetected, second: 42, detail: 'chair'),
        event(SessionEventKind.textRead, second: 331, detail: 'medicine bottle'),
      ]);

      expect(timeline.rows.map((r) => r.stamp), ['00:42', '05:31']);
      expect(timeline.rows.first.text, 'Obstacle detected — chair');
      expect(timeline.rows.last.text, 'Text read — medicine bottle');
    });

    test('orders events even if they arrive shuffled', () {
      final timeline = buildTimeline(walk(), [
        event(SessionEventKind.textRead, second: 300, id: 'b'),
        event(SessionEventKind.obstacleDetected, second: 30, id: 'a'),
      ]);
      expect(timeline.rows.map((r) => r.event.id), ['a', 'b']);
    });

    test('shows hours only when there are hours', () {
      final timeline = buildTimeline(walk(minutes: 90), [
        event(SessionEventKind.obstacleDetected, second: 65),
        event(SessionEventKind.obstacleDetected, second: 3725, id: 'x'),
      ]);
      expect(timeline.rows.first.stamp, '01:05');
      expect(timeline.rows.last.stamp, '1:02:05');
    });

    test('weights hazards and emergencies above routine detections', () {
      final timeline = buildTimeline(walk(), [
        event(SessionEventKind.obstacleDetected, second: 10),
        event(SessionEventKind.stairsDetected, second: 20, id: 'b'),
        event(SessionEventKind.sosFired, second: 30, id: 'c'),
      ]);
      expect(timeline.rows.map((r) => r.weight), [
        EventWeight.ordinary,
        EventWeight.hazard,
        EventWeight.emergency,
      ]);
    });

    test('summarises a session in one line', () {
      final timeline = buildTimeline(walk(), [
        event(SessionEventKind.obstacleDetected, second: 42),
        event(SessionEventKind.textRead, second: 300, id: 'b'),
      ]);
      expect(timeline.summary, contains('10 min'));
      expect(timeline.summary, contains('metres'));
      expect(timeline.summary, contains('2 events'));
    });

    test('a session with no events is still a session', () {
      final timeline = buildTimeline(walk(), const []);
      expect(timeline.rows, isEmpty);
      expect(timeline.summary, contains('0 events'));
      expect(timeline.needsAttention, isFalse);
    });
  });

  group('concerns — what §1.1 is actually asking for', () {
    test('a clean session raises nothing', () {
      final timeline = buildTimeline(walk(), [
        event(SessionEventKind.obstacleDetected, second: 42, detail: 'chair'),
        event(SessionEventKind.guidanceGiven, second: 120, id: 'b'),
      ]);
      expect(timeline.concerns, isEmpty);
      expect(timeline.needsAttention, isFalse);
    });

    test('a cancelled SOS is flagged, not swallowed', () {
      // Either the countdown saved someone from a false alarm, or the button is
      // too easy to hit. Both are things a reviewer should see.
      final timeline = buildTimeline(walk(), [
        event(SessionEventKind.sosArmed, second: 100),
        event(SessionEventKind.sosCancelled, second: 102, id: 'b'),
      ]);
      expect(timeline.needsAttention, isTrue);
      expect(timeline.concerns.first, contains('cancelled'));
      expect(timeline.concerns.first, contains('accident'));
    });

    test('repeated cancellations read as a usability problem', () {
      final timeline = buildTimeline(walk(), [
        for (var i = 0; i < 3; i++)
          event(SessionEventKind.sosCancelled, second: 60 * i, id: 'c$i'),
      ]);
      expect(timeline.concerns.first, contains('too easy to hit'));
    });

    test('a real SOS is flagged', () {
      final timeline =
          buildTimeline(walk(), [event(SessionEventKind.sosFired, second: 90)]);
      expect(timeline.concerns.any((c) => c.contains('SOS was sent')), isTrue);
    });

    test('repeated stairs warnings are worth reviewing', () {
      final timeline = buildTimeline(walk(), [
        for (var i = 0; i < 4; i++)
          event(SessionEventKind.stairsDetected, second: 30 * i, id: 's$i'),
      ]);
      expect(timeline.concerns.any((c) => c.contains('Stairs were detected 4')),
          isTrue);
    });

    test('one or two stairs warnings are just the app working', () {
      final timeline = buildTimeline(walk(), [
        event(SessionEventKind.stairsDetected, second: 30),
        event(SessionEventKind.stairsDetected, second: 60, id: 'b'),
      ]);
      expect(timeline.concerns, isEmpty);
    });

    test('poor positioning is surfaced as a concern about the guidance', () {
      // If the app could barely place the user, its guidance was probably poor
      // too - which is exactly the "system improvement" §1.1 wants found.
      final noisy = journeyFrom('s1', [
        for (var i = 0; i < 10; i++) fix(i * 10, accuracy: 3000),
        for (var i = 10; i < 16; i++) fix(i * 10, offset: i * 0.0001),
      ]);
      final timeline = buildTimeline(noisy, const []);

      expect(timeline.concerns.any((c) => c.contains('unusable')), isTrue);
      expect(timeline.concerns.any((c) => c.contains('guidance may have been')),
          isTrue);
    });

    test('a long session that never moved is flagged', () {
      // Either the user was stuck, or the session should have ended.
      final stationary = journeyFrom(
        's1',
        List.generate(40, (i) => fix(i * 30)),
      );
      final timeline = buildTimeline(stationary, const []);

      expect(timeline.concerns.any((c) => c.contains('without moving')), isTrue);
    });

    test('a short stationary session is not flagged', () {
      final brief = journeyFrom('s1', List.generate(5, (i) => fix(i * 30)));
      expect(buildTimeline(brief, const []).concerns, isEmpty);
    });
  });

  group('event wording', () {
    test('every kind has a description, with and without detail', () {
      for (final kind in SessionEventKind.values) {
        expect(describeEvent(event(kind, second: 0)), isNotEmpty, reason: '$kind');
        expect(describeEvent(event(kind, second: 0, detail: 'x')), isNotEmpty,
            reason: '$kind');
      }
    });

    test('detail is appended rather than replacing the kind', () {
      expect(describeEvent(event(SessionEventKind.stairsDetected,
          second: 0, detail: 'descending')), 'Stairs detected — descending');
    });

    test('serialises for Firestore', () {
      final json = event(SessionEventKind.sosFired, second: 0).toJson();
      expect(json['kind'], 'sosFired');
      expect(json['sessionId'], 's1');
    });
  });
}
