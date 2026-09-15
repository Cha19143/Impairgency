/// Knowing a friend's face, and saying so.
///
/// The testers asked for it: say "hello friend Sam" when Sam is in front of
/// the camera, and next time Sam comes near, hear "Your friend Sam is
/// approaching." This is everything about that which is not a camera or a
/// model - comparing faces, taking a new one down, noticing someone coming
/// closer, and deciding when a name is worth saying.
///
/// What a face is, here, is a short list of numbers from the recogniser. The
/// picture is never kept. The numbers are kept only for people who said yes,
/// out loud, on the spot, and only on the phone (`data/friend_store.dart`).
/// Anyone else the camera sees is compared and forgotten in the same moment.
///
/// Pure, so every rule below is tested without a face.
library;

import 'dart:math' as math;

/// A saved friend.
class Friend {
  const Friend({
    required this.id,
    required this.name,
    required this.embeddings,
    required this.savedAt,
  });

  final String id;
  final String name;

  /// Several views of the same face, each unit length.
  final List<List<double>> embeddings;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'savedAt': savedAt.toUtc().toIso8601String(),
        'embeddings': embeddings,
      };

  /// Null for anything that is not a friend as written by [toJson] - a file
  /// from an older version, or one cut short.
  static Friend? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final savedAt = DateTime.tryParse('${raw['savedAt']}');
    final embeddings = raw['embeddings'];
    if (id is! String || name is! String || savedAt == null) return null;
    if (embeddings is! List || embeddings.isEmpty) return null;
    final views = <List<double>>[];
    for (final view in embeddings) {
      if (view is! List || view.isEmpty || view.any((v) => v is! num)) {
        return null;
      }
      views.add([for (final v in view) (v as num).toDouble()]);
    }
    final length = views.first.length;
    if (views.any((v) => v.length != length)) return null;
    return Friend(id: id, name: name, embeddings: views, savedAt: savedAt);
  }
}

/// Where friends are kept. On the phone only.
abstract interface class FriendStore {
  Future<List<Friend>> load(String owner);
  Future<void> save(String owner, List<Friend> friends);

  /// Deletes every saved face for [owner]; returns how many people that was.
  Future<int> deleteAll(String owner);
}

List<double> l2Normalize(List<double> v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  final norm = math.sqrt(sum);
  if (norm == 0) return List<double>.filled(v.length, 0);
  return [for (final x in v) x / norm];
}

/// Of two unit vectors. 1 is the same direction; 0 is unrelated.
double cosine(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  var dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

/// At or above this, a face is taken to be a friend's.
///
/// A starting point from MobileFaceNet's published numbers, not a measurement
/// on this app's camera: to be calibrated with people who agree to take part,
/// at walking distances and in daylight and indoors, before it is relied on.
const double kFriendThreshold = 0.62;

/// And it has to beat the next friend by this much. Two friends who look
/// alike are not guessed between.
const double kFriendMargin = 0.08;

class FaceMatch {
  const FaceMatch(this.friend, this.similarity);
  final Friend friend;
  final double similarity;
}

/// How like [friend] a face is: its best view.
double similarityTo(List<double> embedding, Friend friend) {
  var best = -1.0;
  for (final view in friend.embeddings) {
    best = math.max(best, cosine(embedding, view));
  }
  return best;
}

/// The friend [embedding] belongs to, or null.
FaceMatch? bestMatch(
  List<double> embedding,
  List<Friend> friends, {
  double threshold = kFriendThreshold,
  double margin = kFriendMargin,
}) {
  FaceMatch? best;
  var second = -1.0;
  for (final friend in friends) {
    final score = similarityTo(embedding, friend);
    if (best == null || score > best.similarity) {
      if (best != null) second = best.similarity;
      best = FaceMatch(friend, score);
    } else if (score > second) {
      second = score;
    }
  }
  if (best == null || best.similarity < threshold) return null;
  if (second >= 0 && best.similarity - second < margin) return null;
  return best;
}

/// A face as the camera saw it, once.
class FaceObservation {
  const FaceObservation({
    required this.embedding,
    required this.width,
    required this.centerX,
    required this.rollDegrees,
    required this.at,
  });

  /// Unit length.
  final List<double> embedding;

  /// Of the face, as a fraction of the frame's width.
  final double width;

  /// Across the frame, 0 at the left edge to 1 at the right.
  final double centerX;

  final double rollDegrees;
  final DateTime at;
}

/// What the scan screen asks of the camera while friends are to be
/// recognised: where to send the faces, and whether one is being taken down -
/// in which case the middle of the frame is searched, person or not.
class FaceWatch {
  FaceWatch({required this.onFaces, this.enrolling = false});

  final void Function(List<FaceObservation> faces) onFaces;
  bool enrolling;
}

/// A name as the recogniser wrote it, as it should be said and shown: "maria
/// clara" becomes "Maria Clara". Null if it is not a name to save.
String? normaliseFriendName(String raw) {
  final words = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty || words.length > 3) return null;
  final name = words
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
  if (name.length > 30 || RegExp(r'[0-9@#/\\]').hasMatch(name)) return null;
  return name;
}

// ---- taking a face down ----------------------------------------------------

/// Samples of one face taken for saving.
const int kEnrollmentSamples = 5;

/// Within this long, or it starts again.
const Duration kEnrollmentWindow = Duration(seconds: 6);

/// Smaller than this across the frame, a face is too far away to learn.
const double kEnrollmentMinWidth = 0.12;

/// Tipped further than this, a face is not a fair sample.
const double kEnrollmentMaxRoll = 25;

/// The samples must agree with each other this well, or they were not all of
/// one person - someone walked through.
const double kEnrollmentAgreement = 0.55;

enum EnrollmentProblem {
  noFace,
  moreThanOneFace,
  tooFar,
  tilted,
  inconsistent,
  alreadySaved,
  tooSlow,
}

/// What to say for each problem, so the person holding the phone can fix it.
String enrollmentProblemPhrase(EnrollmentProblem problem, {String? name}) =>
    switch (problem) {
      EnrollmentProblem.noFace => 'I cannot see a face. Point the phone at '
          '${name ?? 'their'}${name == null ? '' : "'s"} face.',
      EnrollmentProblem.moreThanOneFace =>
        'I can see more than one face. Only ${name ?? 'your friend'} should be '
            'in front of the camera.',
      EnrollmentProblem.tooFar => 'Move closer, about an arm\'s length away.',
      EnrollmentProblem.tilted => 'Hold the phone level with their face.',
      EnrollmentProblem.inconsistent =>
        'The face kept changing, so nothing was saved. Try again with only '
            '${name ?? 'your friend'} in front of the camera.',
      EnrollmentProblem.alreadySaved => 'This face is already saved.',
      EnrollmentProblem.tooSlow =>
        'I could not get a clear look in time, so nothing was saved.',
    };

sealed class EnrollmentStep {
  const EnrollmentStep();
}

/// A good sample; [taken] of [kEnrollmentSamples].
class EnrollmentProgress extends EnrollmentStep {
  const EnrollmentProgress(this.taken);
  final int taken;
}

/// This frame could not be used, and why.
class EnrollmentHint extends EnrollmentStep {
  const EnrollmentHint(this.problem);
  final EnrollmentProblem problem;
}

/// Finished: these views make a friend.
class EnrollmentDone extends EnrollmentStep {
  const EnrollmentDone(this.embeddings);
  final List<List<double>> embeddings;
}

/// Finished without a face to save.
class EnrollmentFailed extends EnrollmentStep {
  const EnrollmentFailed(this.problem, {this.existing});
  final EnrollmentProblem problem;

  /// For [EnrollmentProblem.alreadySaved], whose face it already is.
  final Friend? existing;
}

/// Takes one face down: five clear views within six seconds, all of the same
/// person, and not someone already saved.
class EnrollmentSession {
  EnrollmentSession({required this.friends, required this.startedAt});

  final List<Friend> friends;
  final DateTime startedAt;
  final List<List<double>> _views = [];
  bool _finished = false;

  bool get finished => _finished;

  /// One analysed frame, holding every face the camera found in it.
  EnrollmentStep add(List<FaceObservation> faces, DateTime at) {
    if (_finished) {
      throw StateError('This enrolment has already finished.');
    }
    if (at.difference(startedAt) > kEnrollmentWindow) {
      _finished = true;
      return const EnrollmentFailed(EnrollmentProblem.tooSlow);
    }
    if (faces.isEmpty) return const EnrollmentHint(EnrollmentProblem.noFace);
    if (faces.length > 1) {
      return const EnrollmentHint(EnrollmentProblem.moreThanOneFace);
    }
    final face = faces.single;
    if (face.width < kEnrollmentMinWidth) {
      return const EnrollmentHint(EnrollmentProblem.tooFar);
    }
    if (face.rollDegrees.abs() > kEnrollmentMaxRoll) {
      return const EnrollmentHint(EnrollmentProblem.tilted);
    }
    _views.add(face.embedding);
    if (_views.length < kEnrollmentSamples) {
      return EnrollmentProgress(_views.length);
    }

    _finished = true;
    for (var i = 0; i < _views.length; i++) {
      for (var j = i + 1; j < _views.length; j++) {
        if (cosine(_views[i], _views[j]) < kEnrollmentAgreement) {
          return const EnrollmentFailed(EnrollmentProblem.inconsistent);
        }
      }
    }
    final mean = l2Normalize([
      for (var k = 0; k < _views.first.length; k++)
        _views.fold<double>(0, (sum, v) => sum + v[k]),
    ]);
    final existing = bestMatch(mean, friends, margin: 0);
    if (existing != null) {
      return EnrollmentFailed(EnrollmentProblem.alreadySaved,
          existing: existing.friend);
    }
    return EnrollmentDone(List.unmodifiable(_views));
  }
}

// ---- noticing, and saying ---------------------------------------------------

/// A face this much wider than it was...
const double kApproachGrowth = 1.2;

/// ...within this long, is someone walking up.
const Duration kApproachWindow = Duration(milliseconds: 2500);

/// Whether a friend is coming closer, from how big their face is over time.
class ApproachTracker {
  final Map<String, List<(DateTime, double)>> _widths = {};

  /// Records [width] for [friendId] at [at]; true if they are approaching.
  bool record(String friendId, double width, DateTime at) {
    final history = _widths.putIfAbsent(friendId, () => []);
    history.add((at, width));
    history.removeWhere((entry) => at.difference(entry.$1) > kApproachWindow);
    final smallest = history.map((e) => e.$2).reduce(math.min);
    return history.length >= 2 && width >= smallest * kApproachGrowth;
  }

  void forget(String friendId) => _widths.remove(friendId);
}

/// Seen twice within this long before a name is said: one frame can be
/// wrong.
const Duration kFriendConfirmWithin = Duration(milliseconds: 1500);

/// The same friend is not announced again for this long...
const Duration kFriendCooldown = Duration(seconds: 60);

/// ...and no two announcements come closer than this.
const Duration kAnnouncementGap = Duration(seconds: 8);

/// Decides when a recognised face becomes a sentence.
class FriendAnnouncer {
  final ApproachTracker _approach = ApproachTracker();
  final Map<String, DateTime> _firstSeen = {};
  final Map<String, DateTime> _announced = {};
  DateTime? _lastAnnouncement;

  /// Friends matched lately, for "who is here".
  final Map<String, (Friend, DateTime)> _recent = {};

  /// What to say about [match], seen at [face], or null to stay quiet.
  String? observe(FaceMatch match, FaceObservation face) {
    final friend = match.friend;
    final at = face.at;
    _recent[friend.id] = (friend, at);
    final approaching = _approach.record(friend.id, face.width, at);

    final first = _firstSeen[friend.id];
    if (first == null || at.difference(first) > kFriendConfirmWithin) {
      _firstSeen[friend.id] = at;
      return null;
    }

    final said = _announced[friend.id];
    if (said != null && at.difference(said) < kFriendCooldown) return null;
    final last = _lastAnnouncement;
    if (last != null && at.difference(last) < kAnnouncementGap) return null;

    _announced[friend.id] = at;
    _lastAnnouncement = at;
    _firstSeen.remove(friend.id);
    return friendPhrase(friend.name,
        approaching: approaching, centerX: face.centerX);
  }

  /// Friends seen within [within] of [now], nearest in time first.
  List<Friend> seenRecently(DateTime now,
      {Duration within = const Duration(seconds: 3)}) {
    final seen = _recent.values
        .where((entry) => now.difference(entry.$2) <= within)
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final entry in seen) entry.$1];
  }

  void forget(String friendId) {
    _approach.forget(friendId);
    _firstSeen.remove(friendId);
    _announced.remove(friendId);
    _recent.remove(friendId);
  }
}

/// "Your friend Sam is approaching." - the tester's own words - or where Sam
/// is, when Sam is standing still.
String friendPhrase(String name,
    {required bool approaching, required double centerX}) {
  if (approaching) return 'Your friend $name is approaching.';
  final where = centerX < 0.35
      ? 'on your left'
      : centerX > 0.65
          ? 'on your right'
          : 'in front of you';
  return 'Your friend $name is $where.';
}

/// "Who is here", answered.
String whoIsHerePhrase(List<Friend> seen) => switch (seen.length) {
      0 => 'I do not see anyone you have saved.',
      1 => '${seen.single.name} is here.',
      _ => '${seen.take(seen.length - 1).map((f) => f.name).join(', ')} and '
          '${seen.last.name} are here.',
    };
