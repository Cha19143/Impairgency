import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/faces.dart';

final t0 = DateTime(2026, 9, 15, 9);

List<double> unit(List<double> v) => l2Normalize(v);

Friend friend(String name, List<List<double>> views) => Friend(
    id: 'id-$name', name: name, embeddings: [for (final v in views) unit(v)], savedAt: t0);

FaceObservation face(List<double> embedding,
        {double width = 0.3, double centerX = 0.5, double roll = 0, int ms = 0}) =>
    FaceObservation(
      embedding: unit(embedding),
      width: width,
      centerX: centerX,
      rollDegrees: roll,
      at: t0.add(Duration(milliseconds: ms)),
    );

void main() {
  group('comparing', () {
    test('unit length, and how alike', () {
      final v = l2Normalize([3, 4]);
      expect(v[0], closeTo(0.6, 1e-9));
      expect(cosine(v, v), closeTo(1, 1e-9));
      expect(cosine(unit([1, 0]), unit([0, 1])), closeTo(0, 1e-9));
      expect(l2Normalize([0, 0]), [0, 0]);
    });

    final sam = friend('Sam', [[1, 0, 0, 0], [0.9, 0.1, 0, 0]]);
    final ana = friend('Ana', [[0, 1, 0, 0]]);

    test("a face close to a friend's best view is theirs", () {
      final match = bestMatch(unit([0.95, 0.05, 0.1, 0]), [sam, ana]);
      expect(match?.friend.name, 'Sam');
    });

    test('a stranger is nobody', () {
      expect(bestMatch(unit([0, 0, 1, 0]), [sam, ana]), isNull);
    });

    test('between two look-alikes, nobody is guessed', () {
      final twin = friend('Twin', [[0.98, 0.2, 0, 0]]);
      expect(bestMatch(unit([1, 0.1, 0, 0]), [sam, twin]), isNull);
    });
  });

  group('keeping', () {
    test('a friend is written and read back whole', () {
      final sam = friend('Sam', [[1, 0], [0.8, 0.6]]);
      final again = Friend.fromJson(sam.toJson())!;
      expect(again.name, 'Sam');
      expect(again.embeddings, sam.embeddings);
      expect(again.savedAt, sam.savedAt.toUtc());
    });

    test('anything else is not a friend', () {
      expect(Friend.fromJson(null), isNull);
      expect(Friend.fromJson({'id': 'x', 'name': 'Sam'}), isNull);
      expect(
          Friend.fromJson({
            'id': 'x', 'name': 'Sam', 'savedAt': t0.toIso8601String(),
            'embeddings': [[1, 0], [1]],
          }),
          isNull,
          reason: 'views of different lengths');
    });

    test('a name as heard becomes a name as said', () {
      expect(normaliseFriendName('sam'), 'Sam');
      expect(normaliseFriendName('  maria   clara '), 'Maria Clara');
      expect(normaliseFriendName(''), isNull);
      expect(normaliseFriendName('one two three four'), isNull);
      expect(normaliseFriendName('room 101'), isNull);
    });
  });

  group('taking a face down', () {
    EnrollmentSession session({List<Friend> friends = const []}) =>
        EnrollmentSession(friends: friends, startedAt: t0);

    test('five clear views of one face make a friend', () {
      final s = session();
      for (var i = 1; i <= 4; i++) {
        final step = s.add([face([1, 0.05 * i, 0, 0], ms: i * 400)], t0.add(Duration(milliseconds: i * 400)));
        expect(step, isA<EnrollmentProgress>().having((p) => p.taken, 'taken', i));
      }
      final done = s.add([face([1, 0.3, 0, 0])], t0.add(const Duration(seconds: 2)));
      expect(done, isA<EnrollmentDone>());
      expect((done as EnrollmentDone).embeddings, hasLength(5));
      expect(s.finished, isTrue);
    });

    test('each frame that cannot be used says why', () {
      final s = session();
      EnrollmentProblem? problem(List<FaceObservation> faces) =>
          switch (s.add(faces, t0)) { EnrollmentHint(:final problem) => problem, _ => null };
      expect(problem([]), EnrollmentProblem.noFace);
      expect(problem([face([1, 0]), face([0, 1], centerX: 0.8)]),
          EnrollmentProblem.moreThanOneFace);
      expect(problem([face([1, 0], width: 0.05)]), EnrollmentProblem.tooFar);
      expect(problem([face([1, 0], roll: 40)]), EnrollmentProblem.tilted);
    });

    test('views of two different people are not saved as one', () {
      final s = session();
      for (var i = 0; i < 4; i++) {
        s.add([face([1, 0, 0, 0])], t0);
      }
      final step = s.add([face([0, 1, 0, 0])], t0);
      expect(step, isA<EnrollmentFailed>()
          .having((f) => f.problem, 'problem', EnrollmentProblem.inconsistent));
    });

    test('a face already saved is not saved twice', () {
      final sam = friend('Sam', [[1, 0, 0, 0]]);
      final s = session(friends: [sam]);
      EnrollmentStep? last;
      for (var i = 0; i < 5; i++) {
        last = s.add([face([1, 0.02, 0, 0])], t0);
      }
      expect(last, isA<EnrollmentFailed>()
          .having((f) => f.problem, 'problem', EnrollmentProblem.alreadySaved)
          .having((f) => f.existing?.name, 'existing', 'Sam'));
    });

    test('too slow is given up on', () {
      final s = session();
      expect(s.add([face([1, 0])], t0.add(const Duration(seconds: 7))),
          isA<EnrollmentFailed>()
              .having((f) => f.problem, 'problem', EnrollmentProblem.tooSlow));
    });
  });

  group('saying so', () {
    final sam = friend('Sam', [[1, 0, 0, 0]]);
    final ana = friend('Ana', [[0, 1, 0, 0]]);
    FaceMatch samMatch() => FaceMatch(sam, 0.9);
    FaceMatch anaMatch() => FaceMatch(ana, 0.9);

    test('coming closer is approaching; slowly is not', () {
      final tracker = ApproachTracker();
      expect(tracker.record('s', 0.20, t0), isFalse);
      expect(tracker.record('s', 0.22, t0.add(const Duration(seconds: 1))), isFalse);
      expect(tracker.record('s', 0.25, t0.add(const Duration(seconds: 2))), isTrue);

      final slow = ApproachTracker();
      slow.record('s', 0.20, t0);
      expect(slow.record('s', 0.25, t0.add(const Duration(seconds: 4))), isFalse,
          reason: 'the first sighting has aged out');
    });

    test('once seen twice, and then not again for a minute', () {
      final announcer = FriendAnnouncer();
      expect(announcer.observe(samMatch(), face([1, 0], ms: 0)), isNull,
          reason: 'one frame can be wrong');
      expect(announcer.observe(samMatch(), face([1, 0], ms: 500)),
          'Your friend Sam is in front of you.');
      expect(announcer.observe(samMatch(), face([1, 0], ms: 2000)), isNull);
      expect(announcer.observe(samMatch(), face([1, 0], ms: 2500)), isNull);
      expect(announcer.observe(samMatch(), face([1, 0], ms: 61000)), isNull);
      expect(announcer.observe(samMatch(), face([1, 0], ms: 61500)),
          'Your friend Sam is in front of you.');
    });

    test('no two names within eight seconds', () {
      final announcer = FriendAnnouncer();
      announcer.observe(samMatch(), face([1, 0], ms: 0));
      announcer.observe(samMatch(), face([1, 0], ms: 400));
      announcer.observe(anaMatch(), face([0, 1], ms: 800));
      expect(announcer.observe(anaMatch(), face([0, 1], ms: 1200)), isNull);
      announcer.observe(anaMatch(), face([0, 1], ms: 9000));
      expect(announcer.observe(anaMatch(), face([0, 1], centerX: 0.1, ms: 9400)),
          'Your friend Ana is on your left.');
    });

    test('walking up says approaching, in the words the testers used', () {
      final announcer = FriendAnnouncer();
      announcer.observe(samMatch(), face([1, 0], width: 0.2, ms: 0));
      expect(announcer.observe(samMatch(), face([1, 0], width: 0.3, ms: 1000)),
          'Your friend Sam is approaching.');
    });

    test('who is here', () {
      final announcer = FriendAnnouncer();
      announcer.observe(samMatch(), face([1, 0], ms: 0));
      announcer.observe(anaMatch(), face([0, 1], ms: 500));
      final now = t0.add(const Duration(seconds: 2));
      expect(whoIsHerePhrase(announcer.seenRecently(now)), 'Ana and Sam are here.');
      expect(whoIsHerePhrase(announcer.seenRecently(t0.add(const Duration(seconds: 30)))),
          'I do not see anyone you have saved.');
    });
  });
}
