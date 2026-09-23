import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/faces.dart';
import 'package:impairgency/core/vision/friend_recognition.dart';
import 'package:impairgency/core/voice/voice_commands.dart';

import 'friend_fakes.dart';

void main() {
  late DateTime now;
  late MemoryStore store;
  late List<String> said;
  late FriendRecognition recognition;

  final sam = Friend(
      id: 'f1', name: 'Sam', embeddings: [l2Normalize([1, 0, 0, 0])], savedAt: DateTime(2026));

  FaceObservation face(List<double> v, {double roll = 0, double width = 0.3}) =>
      FaceObservation(
          embedding: l2Normalize(v), width: width, centerX: 0.5, rollDegrees: roll, at: now);

  setUp(() async {
    now = DateTime(2026, 9, 15, 9);
    store = MemoryStore();
    said = [];
    recognition = FriendRecognition(
        store: store, owner: 'u1', say: said.add, now: () => now);
  });

  test('a friend seen twice is named; a stranger never is', () async {
    store.saved['u1'] = [sam];
    await recognition.load();

    recognition.onFaces([face([0, 0, 1, 0])]);
    now = now.add(const Duration(milliseconds: 400));
    recognition.onFaces([face([0, 0, 1, 0])]);
    expect(said, isEmpty);

    recognition.onFaces([face([1, 0.05, 0, 0])]);
    now = now.add(const Duration(milliseconds: 400));
    recognition.onFaces([face([1, 0.05, 0, 0])]);
    expect(said, ['Your friend Sam is in front of you.']);
    expect(recognition.whoIsHere(), 'Sam is here.');
  });

  test("taking a face down: hints, not too often, then saved on the phone",
      () async {
    final result = recognition.enrol('Sam');

    recognition.onFaces(const []);
    now = now.add(const Duration(milliseconds: 400));
    recognition.onFaces(const []);
    expect(said, ["I cannot see a face. Point the phone at Sam's face."],
        reason: 'said once, not every frame');

    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(milliseconds: 400));
      recognition.onFaces([face([0, 1, 0.05 * i, 0])]);
    }
    final step = await result;
    expect(step, isA<EnrollmentDone>());
    // Counted out loud, so whoever holds the phone knows it is working.
    expect(said.skip(1), ['One.', 'Two.', 'Three.', 'Four.', 'Five.']);
    expect(enrollmentResultPhrase(step, name: 'Sam'),
        'Saved Sam. I will tell you when Sam is nearby.');
    expect(store.saved['u1']!.single.name, 'Sam');
    expect(store.saved['u1']!.single.embeddings, hasLength(5));
    expect(recognition.enrolling, isFalse);
  });

  test('forgetting asks first', () async {
    store.saved['u1'] = [sam];
    await recognition.load();

    expect(
        await recognition.forget('sam', ask: (_) async => const ParsedCommand(VoiceCommand.no)),
        'Nothing was deleted.');
    expect(store.saved['u1'], hasLength(1));

    final questions = <String>[];
    expect(
        await recognition.forget('sam', ask: (q) async {
          questions.add(q);
          return const ParsedCommand(VoiceCommand.yes);
        }),
        'Sam is forgotten.');
    expect(questions.single, startsWith('Forget Sam?'));
    expect(store.saved['u1'], isEmpty);
    expect(await recognition.forget('Ana', ask: (_) async => null),
        'There is no one saved called Ana.');
  });

  test('the friend is asked, not the owner', () {
    expect(friendConsentQuestion('Sam'), startsWith('Sam, may this phone remember your face'));
  });

  group('by voice, from anywhere', () {
    final ana = Friend(
        id: 'f2', name: 'Ana', embeddings: [l2Normalize([0, 1, 0, 0])], savedAt: DateTime(2026));

    test('who is saved, said', () async {
      await recognition.load();
      expect(recognition.list(), startsWith('No one is saved yet.'));
      store.saved['u1'] = [sam, ana];
      await recognition.load();
      expect(recognition.list(), 'You have saved 2 people: Sam and Ana.');
    });

    test('renaming keeps the face and changes the name', () async {
      store.saved['u1'] = [sam, ana];
      await recognition.load();
      expect(await recognition.rename('sam', 'samuel'), 'Sam is now Samuel.');
      expect(store.saved['u1']!.first.name, 'Samuel');
      expect(store.saved['u1']!.first.embeddings, sam.embeddings);
      expect(await recognition.rename('lea', 'lee'),
          'There is no one saved called Lea.');
      expect(await recognition.rename('samuel', 'ana'),
          'Someone is already saved as Ana.');
    });

    test('"rename Sam to Samuel" is read as two names', () {
      expect(renameParts('sam to samuel'), ('sam', 'samuel'));
      expect(renameParts('ana cruz as ana reyes'), ('ana cruz', 'ana reyes'));
      expect(renameParts('sam'), isNull);
    });

    test('"forget everyone" is not a friend called Everyone', () {
      expect(matchVoiceCommand('forget everyone'), VoiceCommand.forgetAllFriends);
      expect(matchVoiceCommand('kalimutan lahat'), VoiceCommand.forgetAllFriends);
      expect(parseVoiceCommand('forget sam')?.command, VoiceCommand.forgetFriend);
      expect(parseVoiceCommand('rename sam to samuel')?.argument,
          'sam to samuel');
      expect(matchVoiceCommand('who do i know'), VoiceCommand.listFriends);
    });
  });
}
