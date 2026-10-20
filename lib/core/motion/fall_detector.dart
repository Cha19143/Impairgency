/// A sudden stop, trip, or fall, from the accelerometer.
///
/// A spike on its own is not enough: the spike has to be followed by a short
/// stillness. Walking, a gentle put-down, and a bump that keeps moving do
/// not qualify. One file holds every knob.
///
/// Phone test, without falling: in this file set [kFallImpactThreshold]
/// to `15`, then on Scan or the journey screen give the phone a hard shake
/// and hold it still for about a second. Set [kFallImpactThreshold] back
/// to `25` when the test is done.
library;

import 'dart:math' as math;

/// Total acceleration, in m/s², that counts as an impact.
///
/// Gravity alone is about 9.8. Walking stays under this. Set this to `15`
/// for a phone test so a hard shake counts, then set it back to `25`.
const double kFallImpactThreshold = 25;

/// Below this, the phone is in free fall rather than being held.
const double kFallFreeFallThreshold = 4;

/// Stillness is magnitude near gravity, not near zero and not a shake.
const double kFallStillMin = 7;
const double kFallStillMax = 13;

/// How long the phone must stay in that band after the spike.
const Duration kFallStillWindow = Duration(milliseconds: 700);

/// The stillness has to finish within this of the spike, or the spike is
/// forgotten. A bump in the middle of a walk does not become a fall later.
const Duration kFallPatternWindow = Duration(seconds: 2);

/// Another check cannot start until this has passed.
const Duration kFallCooldown = Duration(seconds: 30);

/// How long the spoken check-in waits for an answer.
const Duration kFallResponseTimeout = Duration(seconds: 15);

/// Said at hazard priority, so navigation and obstacle warnings wait.
const String kFallCheckPhrase = 'Okay ka lang ba?';

/// One accelerometer reading. Axes are m/s² and include gravity.
class MotionSample {
  const MotionSample({
    required this.at,
    required this.x,
    required this.y,
    required this.z,
  });

  final DateTime at;
  final double x;
  final double y;
  final double z;

  double get magnitude => math.sqrt(x * x + y * y + z * z);
}

class FallDetector {
  FallDetector({
    this.impactThreshold = kFallImpactThreshold,
    this.freeFallThreshold = kFallFreeFallThreshold,
    this.stillMin = kFallStillMin,
    this.stillMax = kFallStillMax,
    this.stillWindow = kFallStillWindow,
    this.patternWindow = kFallPatternWindow,
    this.cooldown = kFallCooldown,
  });

  final double impactThreshold;
  final double freeFallThreshold;
  final double stillMin;
  final double stillMax;
  final Duration stillWindow;
  final Duration patternWindow;
  final Duration cooldown;

  DateTime? _armedAt;
  DateTime? _stillSince;
  DateTime? _quietUntil;

  /// True once, when a spike or a free fall has been followed by stillness.
  bool note(MotionSample sample) {
    final mag = sample.magnitude;
    if (mag.isNaN || mag.isInfinite) return false;
    final quiet = _quietUntil;
    if (quiet != null && sample.at.isBefore(quiet)) return false;

    final impact = mag >= impactThreshold;
    final falling = mag <= freeFallThreshold;
    if (impact || falling) {
      _armedAt = sample.at;
      _stillSince = null;
      return false;
    }

    final armed = _armedAt;
    if (armed == null) return false;
    if (sample.at.difference(armed) > patternWindow) {
      _armedAt = null;
      _stillSince = null;
      return false;
    }

    final still = mag >= stillMin && mag <= stillMax;
    if (!still) {
      _stillSince = null;
      return false;
    }
    _stillSince ??= sample.at;
    if (sample.at.difference(_stillSince!) < stillWindow) return false;

    _armedAt = null;
    _stillSince = null;
    _quietUntil = sample.at.add(cooldown);
    return true;
  }
}
