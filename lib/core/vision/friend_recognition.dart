/// Friends, while the camera is on: recognised, announced, saved, forgotten.
///
/// Sits between the faces the scan service finds and the sentences the person
/// hears. Everything it keeps is in [FriendStore], on the phone; everything
/// else - a stranger's face, a frame, a match that did not reach the bar - is
/// dropped in the call that saw it. Nothing about who was seen goes to the
/// guardian's activity, the history, or anywhere off the phone.
///
/// Pure: a store, a clock and a way to speak are passed in.
library;

import 'dart:async';

import '../voice/voice_commands.dart';
import 'faces.dart';

/// Said when recognition is asked for and the person has not agreed to it.
const String kFacesOffPhrase = 'Recognising people is turned off. You can '
    'turn on "Recognise people I know" in Settings, under What the app is '
    'using.';

/// Said when this phone, or this build, cannot recognise anyone.
/// Said when recognition is on but cannot run yet, or at all - by why.
const String kFacesStartingPhrase =
    'The camera is still starting. Say it again in a moment.';
const String kFacesModelsMissingPhrase = 'The face models did not load on '
    'this phone, so people cannot be recognised.';
const String kFacesNoCameraPhrase =
    'The camera is not working, so people cannot be recognised.';

/// Asked when someone says "hello friend" with recognition turned off.
const String kTurnOnFacesQuestion =
    'Recognising people is turned off. Turn it on now? Say yes.';

/// A view of a face, counted out loud while it is taken down: "One." ...
const List<String> _counted = ['One.', 'Two.', 'Three.', 'Four.', 'Five.'];

/// Hints while taking a face down are not repeated more often than this.
const Duration kEnrollmentHintGap = Duration(milliseconds: 2500);

class FriendRecognition {
  FriendRecognition({
    required this.store,
    required this.owner,
    required this.say,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final FriendStore store;

  /// Whose friends: the account's id, or "local" when signed out.
  final String owner;

  /// Speaks, behind hazards.
  final void Function(String sentence) say;

  final DateTime Function() _now;

  List<Friend> _friends = const [];
  List<Friend> get friends => _friends;

  final FriendAnnouncer _announcer = FriendAnnouncer();

  EnrollmentSession? _enrolment;
  Completer<EnrollmentStep>? _enrolled;
  String? _enrolling;
  DateTime? _lastHint;

  /// Taking a face down right now.
  bool get enrolling => _enrolment != null;

  Future<void> load() async {
    _friends = await store.load(owner);
  }

  /// Every face in one analysed frame.
  void onFaces(List<FaceObservation> faces) {
    final enrolment = _enrolment;
    if (enrolment != null) {
      _enrol(enrolment, faces);
      return;
    }
    if (_friends.isEmpty) return;
    for (final face in faces) {
      final match = bestMatch(face.embedding, _friends);
      // Not a friend: compared, and gone with this call.
      if (match == null) continue;
      final sentence = _announcer.observe(match, face);
      if (sentence != null) say(sentence);
    }
  }

  /// "Who is here", from what was recognised in the last few seconds.
  String whoIsHere() => whoIsHerePhrase(_announcer.seenRecently(_now()));

  /// Takes [name]'s face down from the frames that follow. Completes with how
  /// it ended; a [EnrollmentDone] has already been saved.
  Future<EnrollmentStep> enrol(String name) {
    _enrolled?.complete(const EnrollmentFailed(EnrollmentProblem.tooSlow));
    final done = Completer<EnrollmentStep>();
    _enrolled = done;
    _enrolling = name;
    _lastHint = null;
    _enrolment = EnrollmentSession(friends: _friends, startedAt: _now());
    // Frames can stop coming - the camera closed, the screen left. The
    // session's own clock only runs when they arrive.
    return done.future.timeout(kEnrollmentWindow + const Duration(seconds: 3),
        onTimeout: () {
      _finishEnrolment();
      return const EnrollmentFailed(EnrollmentProblem.tooSlow);
    });
  }

  void _enrol(EnrollmentSession session, List<FaceObservation> faces) {
    final step = session.add(faces, _now());
    switch (step) {
      case EnrollmentProgress(:final taken):
        // Counted out loud, so the person holding the phone knows it is
        // working and how far there is to go.
        if (taken >= 1 && taken <= _counted.length) say(_counted[taken - 1]);
      case EnrollmentHint(:final problem):
        final now = _now();
        final last = _lastHint;
        if (last == null || now.difference(last) >= kEnrollmentHintGap) {
          _lastHint = now;
          say(enrollmentProblemPhrase(problem, name: _enrolling));
        }
      case EnrollmentDone(:final embeddings):
        say(_counted.last);
        final name = _enrolling ?? 'Friend';
        final completer = _enrolled;
        _finishEnrolment();
        unawaited(_add(name, embeddings).then(
          (_) => completer?.complete(step),
          onError: (Object e) =>
              completer?.completeError(e),
        ));
      case EnrollmentFailed():
        final completer = _enrolled;
        _finishEnrolment();
        completer?.complete(step);
    }
  }

  void _finishEnrolment() {
    _enrolment = null;
    _enrolled = null;
    _enrolling = null;
  }

  Future<void> _add(String name, List<List<double>> embeddings) async {
    final now = _now();
    final friend = Friend(
      id: 'friend-${now.microsecondsSinceEpoch}',
      name: name,
      embeddings: embeddings,
      savedAt: now,
    );
    _friends = [..._friends, friend];
    await store.save(owner, _friends);
  }

  /// "Forget Sam", asked first and then done. Returns what to say.
  Future<String> forget(
    String rawName, {
    required Future<ParsedCommand?> Function(String question) ask,
  }) async {
    final name = normaliseFriendName(rawName);
    if (name == null) return 'Say forget, and then their name.';
    final match = _friends
        .where((f) => f.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (match == null) return 'There is no one saved called $name.';
    final answer = await ask('Forget ${match.name}? Their face will be '
        'deleted from this phone. Say yes to forget.');
    if (answer?.command != VoiceCommand.yes) return 'Nothing was deleted.';
    await remove(match);
    return '${match.name} is forgotten.';
  }

  /// "Rename Sam to Samuel". Returns what to say.
  Future<String> rename(String from, String to) async {
    final old = normaliseFriendName(from);
    final name = normaliseFriendName(to);
    if (old == null || name == null) {
      return 'Say rename, their name, to, and the new name.';
    }
    final match = _friends
        .where((f) => f.name.toLowerCase() == old.toLowerCase())
        .firstOrNull;
    if (match == null) return 'There is no one saved called $old.';
    if (_friends.any((f) =>
        f.id != match.id && f.name.toLowerCase() == name.toLowerCase())) {
      return 'Someone is already saved as $name.';
    }
    _friends = [
      for (final f in _friends)
        f.id == match.id
            ? Friend(
                id: f.id,
                name: name,
                embeddings: f.embeddings,
                savedAt: f.savedAt)
            : f,
    ];
    await store.save(owner, _friends);
    return '${match.name} is now $name.';
  }

  /// Who is saved, said: "You have saved 2 people: Sam and Ana."
  String list() => friendsListPhrase(_friends);

  Future<void> remove(Friend friend) async {
    _friends = [for (final f in _friends) if (f.id != friend.id) f];
    _announcer.forget(friend.id);
    await store.save(owner, _friends);
  }
}

/// Who is saved, said.
String friendsListPhrase(List<Friend> friends) {
  if (friends.isEmpty) {
    return 'No one is saved yet. Say hello friend, and their name, with them '
        'in front of the phone.';
  }
  final names = friends.map((f) => f.name).toList();
  final said = names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  return names.length == 1
      ? 'You have saved one person: $said.'
      : 'You have saved ${names.length} people: $said.';
}

/// "sam to samuel", "sam as samuel", "sam into samuel": the old name and the
/// new, or null.
(String, String)? renameParts(String argument) {
  final m = RegExp(r'^(.+?)\s+(?:to|as|into|na)\s+(.+)$', caseSensitive: false)
      .firstMatch(argument.trim());
  return m == null ? null : (m.group(1)!, m.group(2)!);
}

/// What to say when taking a face down has ended.
String enrollmentResultPhrase(EnrollmentStep step, {required String name}) =>
    switch (step) {
      EnrollmentDone() => 'Saved $name. I will tell you when $name is nearby.',
      EnrollmentFailed(:final problem, :final existing) =>
        problem == EnrollmentProblem.alreadySaved && existing != null
            ? 'This face is already saved, as ${existing.name}. Nothing new '
                'was saved.'
            : enrollmentProblemPhrase(problem, name: name),
      _ => 'Nothing was saved.',
    };

/// The question the friend is asked, out loud, before anything is kept. The
/// answer has to be theirs: it is their face.
String friendConsentQuestion(String name) =>
    '$name, may this phone remember your face, so it can tell its owner when '
    'you are nearby? It stays on this phone. Say yes to agree.';
