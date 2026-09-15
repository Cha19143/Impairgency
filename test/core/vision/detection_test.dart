import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/detection.dart';
import 'package:impairgency/core/vision/stairs.dart';

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

    test('a low-confidence obstacle is named but not shouted about', () {
      // The threshold for being mentioned is deliberately generous, because a
      // missed obstacle is a collision. "Stop" is the exception: it halts
      // somebody mid-step, and a person stopped for nothing three times stops
      // believing the fourth.
      final guidance = guidanceFor([at(score: 0.4, centerX: 0.5, extent: 0.8)]);
      expect(guidance.phrase, 'Stop. chair right in front of you');
      expect(guidance.urgent, isFalse,
          reason: 'it is worth saying, not worth interrupting for');
    });

    test('the same obstacle, confidently seen, does interrupt', () {
      final guidance = guidanceFor([at(score: 0.9, centerX: 0.5, extent: 0.8)]);
      expect(guidance.urgent, isTrue);
    });

    test('the mention threshold is lower than the shouting one', () {
      expect(kMinScore, lessThan(kUrgentScore));
    });

    test('urgency is set by the primary object', () {
      expect(guidanceFor([at(extent: 0.7)]).urgent, isTrue);
      expect(guidanceFor([at(extent: 0.2)]).urgent, isFalse);
    });
  });

  group('stairs', () {
    const sure =
        StairsReading(confidence: 0.9, treads: 6, spacingRegularity: 0.95);
    const unsure =
        StairsReading(confidence: 0.4, treads: 4, spacingRegularity: 0.5);

    test('a confident reading is said alone, as a hazard', () {
      // Walking into a chair is a bruise; a missed step is a fall. A second
      // object in the same sentence dilutes the one that matters.
      final guidance = guidanceFor(
          [at(label: 'chair', centerX: 0.5, extent: 0.4)],
          stairs: sure);
      expect(guidance.phrase, kStairsAhead);
      expect(guidance.urgent, isTrue);
      expect(guidance.label, 'stairs');
    });

    test('an object urgent in its own right is still named first', () {
      // A zebra crossing reads as stairs to the banding heuristic. A car right
      // in front of someone standing on one is a car.
      final guidance = guidanceFor(
          [at(label: 'car', centerX: 0.5, extent: 0.7)],
          stairs: sure);
      expect(guidance.phrase, 'Stop. car right in front of you');
    });

    test('an unsure reading says nothing about stairs', () {
      expect(guidanceFor(const [], stairs: unsure).phrase, kPathClear);
      expect(
          guidanceFor([at(label: 'chair', extent: 0.4)], stairs: unsure).phrase,
          isNot(contains('Stairs')));
    });

    test('never up or down: one camera cannot tell', () {
      expect(kStairsAhead.toLowerCase(), isNot(contains('down')));
      expect(kStairsAhead.toLowerCase(), isNot(contains(' up')));
    });

    test('repeated as a hazard is: not until it has had time to be heard', () {
      final now = DateTime.utc(2026, 9, 16, 9);
      bool again(Duration after) => shouldSpeak(
            phrase: kStairsAhead,
            urgent: true,
            lastPhrase: kStairsAhead,
            lastSpokenAt: now,
            now: now.add(after),
          );
      expect(again(const Duration(seconds: 1)), isFalse);
      expect(again(kHazardRepeat), isTrue);
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

    test('a new hazard goes through immediately', () {
      // "Stop" arriving three seconds late is worse than not arriving.
      expect(
        shouldSpeak(
            phrase: 'Stop. chair right in front of you',
            urgent: true,
            lastPhrase: 'table close, ahead',
            lastSpokenAt: now,
            now: now),
        isTrue,
      );
    });

    test('the same hazard is not reissued with every camera frame', () {
      // The tester's bug: "Stop, tree in front of you" restarted on every
      // frame, so they heard "Stop. Stop. Stop." and never the tree.
      const phrase = 'Stop. tree right in front of you';
      expect(
        shouldSpeak(
            phrase: phrase,
            urgent: true,
            lastPhrase: phrase,
            lastSpokenAt: now,
            now: now.add(const Duration(milliseconds: 200))),
        isFalse,
      );
      expect(
        shouldSpeak(
            phrase: phrase,
            urgent: true,
            lastPhrase: phrase,
            lastSpokenAt: now,
            now: now.add(const Duration(seconds: 2))),
        isFalse,
        reason: 'long enough to have been said once, not yet to say again',
      );
    });

    test('a hazard that is still there is repeated, after it has been heard',
        () {
      const phrase = 'Stop. tree right in front of you';
      expect(
        shouldSpeak(
            phrase: phrase,
            urgent: true,
            lastPhrase: phrase,
            lastSpokenAt: now,
            now: now.add(kHazardRepeat)),
        isTrue,
      );
    });

    test('the hazard repeat is shorter than the ordinary cooldown', () {
      // Still there means still dangerous; it is repeated sooner than chatter.
      expect(kHazardRepeat, greaterThan(Duration.zero));
      expect(kHazardRepeat, lessThanOrEqualTo(kSpeechCooldown + const Duration(seconds: 1)));
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
