
library;

import 'dart:math' as math;

import '../location/location_fix.dart';
import '../places/geo.dart';
import 'destination.dart';

enum Turn {
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  turnAround,

  /// Close enough that any further instruction would be noise.
  arrived,

  /// No usable heading. GPS reports the direction of *travel*, not the
  /// direction the phone faces, so it is meaningless until the user has
  /// walked a few steps.
  unknown,
}

/// Initial bearing from one point to another, in degrees clockwise from
/// north, 0 to 360.
double bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = _rad(lat1);
  final phi2 = _rad(lat2);
  final dLambda = _rad(lng2 - lng1);
  final y = math.sin(dLambda) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// How far the destination lies from straight ahead: negative is left,
/// positive is right, in (-180, 180].
double relativeAngle({required double heading, required double bearing}) {
  var delta = (bearing - heading) % 360;
  if (delta > 180) delta -= 360;
  if (delta <= -180) delta += 360;
  return delta;
}

/// Within this many metres the user has arrived. GPS on a phone is rarely
/// better than ten; asking someone to close the last five is asking them to
/// walk in circles.
const double kArrivedMetres = 15;

Turn turnFor({
  required double distanceMetres,
  required double? relative,
  double? accuracyMetres,
}) {
  if (distanceMetres <= math.max(kArrivedMetres, (accuracyMetres ?? 0) * 0.8)) {
    return Turn.arrived;
  }
  if (relative == null) return Turn.unknown;
  final a = relative.abs();
  final left = relative < 0;
  if (a <= 20) return Turn.straight;
  if (a <= 50) return left ? Turn.slightLeft : Turn.slightRight;
  if (a <= 120) return left ? Turn.left : Turn.right;
  if (a <= 160) return left ? Turn.sharpLeft : Turn.sharpRight;
  return Turn.turnAround;
}

/// Distances the way a person says them: "about 50 metres", "about 1.2
/// kilometres". Rounded, because a GPS distance of 137 metres is not 137.
String describeDistance(double metres) {
  if (metres < 10) return 'a few metres';
  if (metres < 100) return 'about ${(metres / 10).round() * 10} metres';
  if (metres < 1000) return 'about ${(metres / 50).round() * 50} metres';
  final km = metres / 1000;
  return km < 10
      ? 'about ${km.toStringAsFixed(1)} kilometres'
      : 'about ${km.round()} kilometres';
}

class NavigationPrompt {
  const NavigationPrompt({
    required this.turn,
    required this.distanceMetres,
    required this.phrase,
  });

  final Turn turn;
  final double distanceMetres;
  final String phrase;
}

String _turnWords(Turn turn) => switch (turn) {
      Turn.straight => 'Keep going straight',
      Turn.slightLeft => 'Bear slightly left',
      Turn.left => 'Turn left',
      Turn.sharpLeft => 'Turn sharply left',
      Turn.slightRight => 'Bear slightly right',
      Turn.right => 'Turn right',
      Turn.sharpRight => 'Turn sharply right',
      Turn.turnAround => 'Turn around',
      Turn.arrived => 'You have arrived',
      Turn.unknown => 'Walk a few steps',
    };

/// The sentence for one reading.
NavigationPrompt promptFor({
  required LocationFix here,
  required Destination to,
  double? heading,
}) {
  final distance = metresBetween(
      here.latitude, here.longitude, to.latitude, to.longitude);
  final bearing =
      bearingDegrees(here.latitude, here.longitude, to.latitude, to.longitude);
  final relative =
      heading == null ? null : relativeAngle(heading: heading, bearing: bearing);
  final turn = turnFor(
    distanceMetres: distance,
    relative: relative,
    accuracyMetres: here.accuracyMetres,
  );
  final phrase = switch (turn) {
    Turn.arrived => 'You have arrived at ${to.label}.',
    Turn.unknown => 'Walk a few steps so I can tell which way you are facing. '
        '${to.label} is ${describeDistance(distance)} away.',
    _ => '${_turnWords(turn)}. ${to.label} is ${describeDistance(distance)} '
        'away.',
  };
  return NavigationPrompt(turn: turn, distanceMetres: distance, phrase: phrase);
}

/// Repeat a prompt whose turn has not changed no more often than this.
const Duration kNavigationRepeat = Duration(seconds: 20);

/// Or when the distance has changed by this much, whichever comes first.
const double kNavigationProgressMetres = 30;

/// Whether to say [next] now, given what was last said and when.
///
/// The do-not-nag rule. A turn that has changed is said at once; the same
/// turn is repeated only after [kNavigationRepeat] or a decent stretch of
/// progress; "unknown" is said once and then left alone until something is
/// known; "arrived" is said exactly once.
bool shouldAnnounce({
  required NavigationPrompt next,
  required NavigationPrompt? last,
  required DateTime? lastAt,
  required DateTime now,
}) {
  if (last == null || lastAt == null) return true;
  if (last.turn == Turn.arrived) return false;
  if (next.turn != last.turn) {
    // Flapping between "straight" and "slightly left" on a noisy heading
    // would be a running commentary. Neighbours wait for the timer.
    if (_neighbours(next.turn, last.turn)) {
      return now.difference(lastAt) >= kNavigationRepeat;
    }
    return true;
  }
  if (next.turn == Turn.unknown) return false;
  if (now.difference(lastAt) >= kNavigationRepeat) return true;
  return (last.distanceMetres - next.distanceMetres).abs() >=
      kNavigationProgressMetres;
}

bool _neighbours(Turn a, Turn b) {
  const pairs = {
    (Turn.straight, Turn.slightLeft),
    (Turn.straight, Turn.slightRight),
    (Turn.slightLeft, Turn.left),
    (Turn.slightRight, Turn.right),
    (Turn.left, Turn.sharpLeft),
    (Turn.right, Turn.sharpRight),
    (Turn.sharpLeft, Turn.turnAround),
    (Turn.sharpRight, Turn.turnAround),
  };
  return pairs.contains((a, b)) || pairs.contains((b, a));
}

/// One journey's worth of prompts, with the rule above applied.
///
/// Feed it every fix; it hands back the sentences worth saying and nothing
/// else. The heading comes from the fix when the user is moving fast enough
/// for GPS to know it, and is otherwise null.
class NavigationSession {
  NavigationSession({required this.destination, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Destination destination;
  final DateTime Function() _now;

  NavigationPrompt? _last;
  DateTime? _lastAt;
  bool _arrived = false;

  NavigationPrompt? get last => _last;
  bool get arrived => _arrived;

  /// The next thing to say, or null to stay quiet.
  NavigationPrompt? update(LocationFix fix) {
    if (_arrived) return null;
    final heading = fix.usableHeading;
    final prompt = promptFor(here: fix, to: destination, heading: heading);
    final now = _now();
    if (!shouldAnnounce(next: prompt, last: _last, lastAt: _lastAt, now: now)) {
      return null;
    }
    _last = prompt;
    _lastAt = now;
    if (prompt.turn == Turn.arrived) _arrived = true;
    return prompt;
  }

  /// What the screen shows between prompts, always current.
  String statusFor(LocationFix fix) =>
      promptFor(here: fix, to: destination, heading: fix.usableHeading).phrase;
}

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;
