/// What the camera found, and how urgently to say it.
///
/// Ported from `cprwire`'s scan screen, which got this part right. Kept pure so
/// the decisions — which object to mention, how urgent it is, when to stay
/// quiet — can be tested without a camera or a model.
library;

import 'dart:math' as math;

import 'class_risk.dart';
import 'depth.dart';
import 'stairs.dart';

export 'class_risk.dart' show canBeHazard, riskWeight;

enum Proximity { veryClose, close, far }

/// Where a detection is, as fractions of the upright frame.
class DetectionBox {
  const DetectionBox(this.left, this.top, this.right, this.bottom);
  final double left;
  final double top;
  final double right;
  final double bottom;
}

class Detection {
  const Detection({
    required this.label,
    required this.score,
    required this.centerX,
    required this.extent,
    this.box,
  });

  /// The whole box, when the model gave one. Where a person's head is, for
  /// recognising a friend; nothing about what is said depends on it.
  final DetectionBox? box;

  final String label;

  /// Model confidence, 0 to 1.
  final double score;

  /// Horizontal centre in the frame, 0 (left edge) to 1 (right edge).
  final double centerX;

  /// The larger of the box's width and height, as a fraction of the frame.
  /// Bigger means nearer — the only depth cue a single camera has.
  final double extent;

  /// "Close" from a quarter of the frame, not a third: it was said too late
  /// to step round what it named. "Very close" - the "Stop" - stays where it
  /// was, because a Stop said for nothing is a Stop believed less.
  Proximity get proximity {
    if (extent > 0.55) return Proximity.veryClose;
    if (extent > 0.25) return Proximity.close;
    return Proximity.far;
  }

  String get direction {
    if (centerX < 0.35) return 'on your left';
    if (centerX > 0.65) return 'on your right';
    return 'ahead';
  }

  /// Centred obstacles are the ones you walk into, so they outrank something
  /// equally near but off to the side - and a car outranks a chair the same
  /// size ([riskWeight]).
  double get risk {
    final centrality = 1.0 - (centerX - 0.5).abs() * 2.0;
    return extent * (1.0 + centrality) * riskWeight(label);
  }

  String get phrase => switch (proximity) {
        Proximity.veryClose => direction == 'ahead' && canBeHazard(label)
            ? 'Stop. $label right in front of you'
            : '$label very close $direction',
        Proximity.close => '$label close, $direction',
        Proximity.far => '$label $direction',
      };
}

/// One analysed camera frame: the objects in it, and the floor under them.
///
/// One value rather than two arguments, because it is one observation: a
/// caller should not be able to pair up an earlier frame's stairs with this
/// frame's chair.
class ScanFrame {
  const ScanFrame({
    required this.detections,
    this.stairs = StairsReading.none,
    this.depth = DepthReading.none,
    this.notice,
  });

  final List<Detection> detections;
  final StairsReading stairs;

  /// Something in the way that has no name - see `depth.dart`.
  final DepthReading depth;

  /// Said once, and not about the frame: the depth model was switched off on
  /// a phone too slow for it.
  final String? notice;
}

/// What to say about a frame, or null to stay silent.
class Guidance {
  const Guidance({
    required this.phrase,
    required this.urgent,
    this.label,
    this.nothingSeen = false,
  });

  final String phrase;

  /// The nearest object's name, for anything that records what was said.
  final String? label;

  /// Something is close enough to walk into. Interrupts, and buzzes.
  final bool urgent;

  /// The model named nothing in view. Said when it becomes true, and seldom
  /// after that: it is not news.
  final bool nothingSeen;
}

/// Said when the model names nothing in view.
///
/// It used to say "Path looks clear". The model knows 80 kinds of thing, and
/// walls, doors, posts, kerbs and steps are none of them, so a frame with
/// nothing named in it is not a clear path - and a sentence that promised one
/// is a sentence someone walks into a wall believing.
const String kNoKnownObjects = 'No known objects in view';

/// Said for stairs, and nothing else is said with it.
///
/// No direction beyond "ahead", because the heuristic only looks at the lower
/// centre of the frame; and no "up" or "down", because ascending and
/// descending treads look identical to one camera and guessing would be worse
/// than the person finding out with their cane.
const String kStairsAhead = 'Stop. Stairs ahead.';

/// Confidence below which a detection is noise rather than an object.
///
/// 0.35, not the 0.5 an object detector is usually demonstrated at, and the
/// difference was measured rather than guessed. Against 846 annotated images,
/// raising the bar to 0.5 loses about one nearby obstacle in twenty and buys
/// back a few points of precision. That is the wrong way round for this app:
/// an obstacle it fails to mention is someone walking into it, and an object
/// it mentions that is not there is a sentence they ignore.
const double kMinScore = 0.35;

/// Confidence below which the app will describe something but not interrupt
/// for it.
///
/// The asymmetry above has one exception. "Stop" is the only thing this app
/// says that makes someone halt mid-step in a street, and a person who is made
/// to stop for nothing three times stops believing the fourth. So a low
/// confidence is enough to be *mentioned* and not enough to be *shouted*: the
/// obstacle still gets named, at the volume the evidence supports.
const double kUrgentScore = 0.5;

/// Said for something in the way that the object model has no name for.
const String kSomethingAhead = 'Stop. Something right in front of you.';

/// The same, not yet close enough to stop for.
String somethingPhrase(DepthDirection direction) => switch (direction) {
      DepthDirection.left => 'Something on your left. Slow down.',
      DepthDirection.right => 'Something on your right. Slow down.',
      DepthDirection.ahead => 'Something ahead. Slow down.',
    };

/// Chooses what to say about one frame.
///
/// Mentions a second object only when it is near enough to matter. Listing
/// everything in view is what makes these apps unusable — a user walking gets
/// one useful sentence per few seconds, not an inventory.
///
/// In order: an object urgent in its own right; stairs, when [stairs] is sure
/// of them, said alone - walking into a chair is a bruise and a missed step is
/// a fall, but a zebra crossing reads as stairs to the banding heuristic and a
/// car right in front of someone standing on one has to be named as a car;
/// something in the way that has no name, when [depth] is sure of it and no
/// object big enough to be it was named on that side; then the objects.
Guidance guidanceFor(
  List<Detection> detections, {
  StairsReading stairs = StairsReading.none,
  DepthReading depth = DepthReading.none,
}) {
  final objects = _objectGuidance(detections);
  if (objects.urgent) return objects;
  if (stairs.isStairs) {
    return const Guidance(phrase: kStairsAhead, urgent: true, label: 'stairs');
  }
  if (depth.isBlocked && !_namedOn(depth.direction, detections)) {
    return Guidance(
      phrase:
          depth.isUrgent ? kSomethingAhead : somethingPhrase(depth.direction),
      urgent: depth.isUrgent,
      label: 'obstacle',
    );
  }
  return objects;
}

/// Whether an object big enough to be what [direction]'s depth found was
/// already named there. The chair the detector saw is the same thing the
/// depth model saw; saying both is saying one thing twice.
bool _namedOn(DepthDirection direction, List<Detection> detections) {
  final side = switch (direction) {
    DepthDirection.left => 'on your left',
    DepthDirection.right => 'on your right',
    DepthDirection.ahead => 'ahead',
  };
  return detections.any((d) =>
      d.score >= kMinScore && d.extent > 0.30 && d.direction == side);
}

Guidance _objectGuidance(List<Detection> detections) {
  final real = detections.where((d) => d.score >= kMinScore).toList()
    ..sort((a, b) => b.risk.compareTo(a.risk));

  if (real.isEmpty) {
    return const Guidance(
        phrase: kNoKnownObjects, urgent: false, nothingSeen: true);
  }

  final primary = real.first;
  var phrase = primary.phrase;

  final secondary = real.skip(1).where(
        (d) => d.proximity != Proximity.far && d.label != primary.label,
      );
  if (secondary.isNotEmpty) {
    final other = secondary.first;
    phrase = '$phrase. ${other.label} ${other.direction}';
  }

  return Guidance(
    phrase: phrase,
    // Never for something held in a hand: a phone at the lens is very close
    // and not a reason to stop walking.
    urgent: primary.proximity == Proximity.veryClose &&
        primary.score >= kUrgentScore &&
        canBeHazard(primary.label),
    label: primary.label,
  );
}

/// How long to stay quiet after saying something ordinary.
const Duration kSpeechCooldown = Duration(seconds: 3);

/// How long the *same* hazard waits before it is shouted again.
///
/// Shorter than [kSpeechCooldown] because a hazard that is still there is
/// still a hazard — but not zero. Zero is the bug the tester reported: the
/// warning was reissued with every camera frame, each one restarting the
/// sentence, and the user heard "Stop. Stop. Stop." and never what to stop
/// for. Long enough for the whole sentence to be said; the speech queue
/// itself refuses to restart a hazard that is still being spoken.
const Duration kHazardRepeat = Duration(seconds: 4);

/// How long "no known objects" waits before it is said again. It was said
/// every three seconds on an empty street, and a sentence that is always
/// there is one nobody listens to when something else is said.
const Duration kQuietRepeat = Duration(seconds: 20);

/// How long a different ordinary sentence waits after the last one. Shorter
/// than it was (900 ms): a new object was named late enough to be walked into.
const Duration kChangeGap = Duration(milliseconds: 600);

/// Whether to actually speak [phrase] now.
///
/// Four rules, all about not talking over yourself. The same sentence is not
/// repeated until it has been quiet for a while - a long while when it is
/// [quiet], saying nothing was seen; a *new* urgent warning goes through
/// immediately, because "stop" arriving three seconds late is worse than not
/// arriving; the *same* urgent warning is repeated, but only after it has had
/// time to be heard in full.
bool shouldSpeak({
  required String phrase,
  required bool urgent,
  required String? lastPhrase,
  required DateTime? lastSpokenAt,
  required DateTime now,
  bool quiet = false,
  Duration cooldown = kSpeechCooldown,
  Duration hazardRepeat = kHazardRepeat,
}) {
  if (lastSpokenAt == null) return true;
  if (urgent) {
    if (phrase != lastPhrase) return true;
    return now.difference(lastSpokenAt) >= hazardRepeat;
  }
  if (phrase != lastPhrase) {
    // A different sentence still waits a moment, or a scene with two objects
    // alternating would produce a stream of chatter.
    return now.difference(lastSpokenAt) >= kChangeGap;
  }
  return now.difference(lastSpokenAt) >= (quiet ? kQuietRepeat : cooldown);
}

/// Converts a model box to a [Detection].
Detection detectionFrom({
  required String label,
  required double score,
  required double xMin,
  required double yMin,
  required double xMax,
  required double yMax,
}) =>
    Detection(
      label: label,
      score: score,
      centerX: (xMin + xMax) / 2,
      extent: math.max(xMax - xMin, yMax - yMin),
      box: DetectionBox(xMin, yMin, xMax, yMax),
    );
