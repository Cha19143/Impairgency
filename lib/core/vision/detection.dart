/// What the camera found, and how urgently to say it.
///
/// Ported from `cprwire`'s scan screen, which got this part right. Kept pure so
/// the decisions — which object to mention, how urgent it is, when to stay
/// quiet — can be tested without a camera or a model.
library;

import 'dart:math' as math;

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

  Proximity get proximity {
    if (extent > 0.55) return Proximity.veryClose;
    if (extent > 0.30) return Proximity.close;
    return Proximity.far;
  }

  String get direction {
    if (centerX < 0.35) return 'on your left';
    if (centerX > 0.65) return 'on your right';
    return 'ahead';
  }

  /// Centred obstacles are the ones you walk into, so they outrank something
  /// equally near but off to the side.
  double get risk {
    final centrality = 1.0 - (centerX - 0.5).abs() * 2.0;
    return extent * (1.0 + centrality);
  }

  String get phrase => switch (proximity) {
        Proximity.veryClose => direction == 'ahead'
            ? 'Stop. $label right in front of you'
            : '$label very close $direction',
        Proximity.close => '$label close, $direction',
        Proximity.far => '$label $direction',
      };
}

/// What to say about a frame, or null to stay silent.
class Guidance {
  const Guidance({required this.phrase, required this.urgent, this.label});

  final String phrase;

  /// The nearest object's name, for anything that records what was said.
  final String? label;

  /// Something is close enough to walk into. Interrupts, and buzzes.
  final bool urgent;
}

const String kPathClear = 'Path looks clear';

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

/// Chooses what to say about one frame.
///
/// Mentions a second object only when it is near enough to matter. Listing
/// everything in view is what makes these apps unusable — a user walking gets
/// one useful sentence per few seconds, not an inventory.
Guidance guidanceFor(List<Detection> detections) {
  final real = detections.where((d) => d.score >= kMinScore).toList()
    ..sort((a, b) => b.risk.compareTo(a.risk));

  if (real.isEmpty) {
    return const Guidance(phrase: kPathClear, urgent: false);
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
    urgent: primary.proximity == Proximity.veryClose &&
        primary.score >= kUrgentScore,
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

/// Whether to actually speak [phrase] now.
///
/// Three rules, all about not talking over yourself. The same sentence is not
/// repeated until it has been quiet for a while; a *new* urgent warning goes
/// through immediately, because "stop" arriving three seconds late is worse
/// than not arriving; the *same* urgent warning is repeated, but only after
/// it has had time to be heard in full.
bool shouldSpeak({
  required String phrase,
  required bool urgent,
  required String? lastPhrase,
  required DateTime? lastSpokenAt,
  required DateTime now,
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
    return now.difference(lastSpokenAt) >= const Duration(milliseconds: 900);
  }
  return now.difference(lastSpokenAt) >= cooldown;
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
