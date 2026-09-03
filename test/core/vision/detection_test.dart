import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/detection.dart';

Detection at({
  String label = 'chair',
  double score = 0.9,
  double centerX = 0.5,
  double extent = 0.2,
}) =>
    Detection(label: label, score: score, centerX: centerX, extent: extent);

void main() {
  group('how near, and which way', () {
    test('a bigger box is a nearer object — the only depth cue one camera has',
        () {
      expect(at(extent: 0.7).proximity, Proximity.veryClose);
      expect(at(extent: 0.4).proximity, Proximity.close);
      expect(at(extent: 0.1).proximity, Proximity.far);
    });

    test('direction is left, right, or ahead', () {
      expect(at(centerX: 0.1).direction, 'on your left');
      expect(at(centerX: 0.9).direction, 'on your right');
      expect(at(centerX: 0.5).direction, 'ahead');
    });

    test('centred obstacles outrank equally near ones off to the side', () {
      // The one you walk into matters more than the one you pass.
      final centred = at(centerX: 0.5, extent: 0.4);
      final beside = at(centerX: 0.05, extent: 0.4);
      expect(centred.risk, greaterThan(beside.risk));
    });
  });

  group('what it says', () {
    test('something directly ahead and close says stop', () {
      expect(at(centerX: 0.5, extent: 0.7).phrase,
          'Stop. chair right in front of you');
    });

    test('something close but to the side does not say stop', () {
      expect(at(centerX: 0.9, extent: 0.7).phrase,
          'chair very close on your right');
    });

    test('something far is mentioned without alarm', () {
      expect(at(centerX: 0.5, extent: 0.1).phrase, 'chair ahead');
    });
  });

  group('choosing what to say about a frame', () {
    test('an empty frame is a clear path', () {
      expect(guidanceFor(const []).phrase, kPathClear);
      expect(guidanceFor(const []).urgent, isFalse);
    });

    test('low-confidence boxes are noise, not objects', () {
      expect(guidanceFor([at(score: 0.2, extent: 0.8)]).phrase, kPathClear);
    });

    test('the riskiest object is the one announced', () {
      final guidance = guidanceFor([
        at(label: 'bin', centerX: 0.05, extent: 0.5),
        at(label: 'chair', centerX: 0.5, extent: 0.5),
      ]);
      expect(guidance.phrase, startsWith('chair'));
    });

    test('a second object is mentioned only when it is near enough to matter',
        () {
      // Listing everything in view is what makes these apps unusable.
      final withDistant = guidanceFor([
        at(label: 'chair', extent: 0.6),
        at(label: 'plant', centerX: 0.9, extent: 0.05),
      ]);
      expect(withDistant.phrase, isNot(contains('plant')));

      final withNear = guidanceFor([
        at(label: 'chair', extent: 0.6),
        at(label: 'table', centerX: 0.9, extent: 0.4),
      ]);
      expect(withNear.phrase, contains('table on your right'));
    });

    test('never names the same object twice', () {
      final guidance = guidanceFor([
        at(label: 'chair', centerX: 0.5, extent: 0.6),
        at(label: 'chair', centerX: 0.8, extent: 0.4),
      ]);
      expect('chair'.allMatches(guidance.phrase).length, 1);
    });

    test('urgency is set by the primary object', () {
      expect(guidanceFor([at(extent: 0.7)]).urgent, isTrue);
      expect(guidanceFor([at(extent: 0.2)]).urgent, isFalse);
    });
  });

  group('not talking over itself', () {
    final now = DateTime.utc(2026, 9, 3, 12);

    test('the first thing is always said', () {
      expect(
        shouldSpeak(
            phrase: 'chair ahead',
            urgent: false,
            lastPhrase: null,
            lastSpokenAt: null,
            now: now),
        isTrue,
      );
    });

    test('the same sentence waits out the cooldown', () {
      expect(
        shouldSpeak(
            phrase: 'chair ahead',
            urgent: false,
            lastPhrase: 'chair ahead',
            lastSpokenAt: now.subtract(const Duration(seconds: 1)),
            now: now),
        isFalse,
      );
      expect(
        shouldSpeak(
            phrase: 'chair ahead',
            urgent: false,
            lastPhrase: 'chair ahead',
            lastSpokenAt: now.subtract(const Duration(seconds: 4)),
            now: now),
        isTrue,
      );
    });

    test('a different sentence still waits a moment', () {
      // Two objects alternating would otherwise produce a stream of chatter.
      expect(
        shouldSpeak(
            phrase: 'table ahead',
            urgent: false,
            lastPhrase: 'chair ahead',
            lastSpokenAt: now.subtract(const Duration(milliseconds: 200)),
            now: now),
        isFalse,
      );
    });

    test('urgent always goes through immediately', () {
      // "Stop" arriving three seconds late is worse than not arriving.
      expect(
        shouldSpeak(
            phrase: 'Stop. chair right in front of you',
            urgent: true,
            lastPhrase: 'Stop. chair right in front of you',
            lastSpokenAt: now,
            now: now),
        isTrue,
      );
    });
  });

  group('reading model output', () {
    test('takes the centre and the larger side from a box', () {
      final d = detectionFrom(
          label: 'chair', score: 0.9,
          xMin: 0.2, yMin: 0.1, xMax: 0.6, yMax: 0.8);
      expect(d.centerX, closeTo(0.4, 1e-9));
      expect(d.extent, closeTo(0.7, 1e-9), reason: 'height is the larger side');
    });
  });
}
