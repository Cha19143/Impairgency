/// §2.A.1 — what the object model has no name for: walls, doors, posts, kerbs,
/// the edge of a table.
///
/// YOLO11n names 80 kinds of thing, and a wall is none of them. So a frame
/// with a wall filling it used to be described as a clear path. This reads a
/// second model, MiDaS v2.1 small (MIT), which names nothing and instead says,
/// for every pixel, how near it is compared with the rest of the frame. Near
/// relative to *what the floor would be* at that height in the picture is
/// something standing on the floor, in the way.
///
/// **What it actually detects is a surface rising out of the floor in the
/// walking corridor.** For a camera looking at flat ground, nearness goes up
/// steadily from the top of the ground to the bottom of the picture - a
/// straight line, row by row, whatever the model's own scale. That line is
/// fitted to the bottom of the picture, where the floor right in front of the
/// user is, and carried up the corridor. Rows that stand well above it, for
/// long enough, are something in the way.
///
/// It knows nothing of what the thing is, and it guesses at slopes: a ramp
/// down reads as floor that stops, a kerb seen from the road as a wall, the
/// side of a narrow corridor as something beside you. That is why
/// [kDepthWarnings] is off until a device check says what it gets wrong - see
/// `docs/VISION.md`, "Depth".
///
/// Pure, and takes the model's output as a flat list, so every case below is
/// a test rather than a walk into a wall.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Whether the scan screens run the depth model and warn from it.
///
/// Off unless a build asks for it with `--dart-define=DEPTH_WARNINGS=true`,
/// and the model file is not in the repository: a device-check build adds it.
const bool kDepthWarnings = bool.fromEnvironment('DEPTH_WARNINGS');

/// Where a device-check build puts MiDaS v2.1 small. Not in the repository:
/// see `docs/VISION.md`, "Depth".
const String kDepthModelAsset = 'assets/models/model_opt.tflite';

/// The side of the square the model reads and writes.
const int kDepthSide = 256;

/// How far above the floor line, in the frame's own range of nearness, a row
/// has to stand to be something in the way.
const double kAboveFloor = 0.15;

/// The fewest rows, as a fraction of the picture, a block has to span. A
/// shorter run is a shadow, a pothole's rim, or noise.
const double kBlockedRows = 0.08;

/// The rows that make a block certain, as a fraction of the picture.
const double kSureRows = 0.15;

/// Below this, say nothing. As with stairs, silence rather than a guess.
const double kDepthMinConfidence = 0.6;

/// Nearness, 0 to 1 in the frame's range, from which a block ahead is a
/// "Stop".
const double kDepthUrgent = 0.8;

/// The floor has to get nearer towards the bottom of the picture by at least
/// this much per picture height, or the bottom of the picture is not floor.
const double kMinFloorSlope = 0.3;

/// The corridor searched: from just below the middle of the picture to just
/// above the bottom, where the floor line is fitted.
const double _corridorTop = 0.45;
const double _corridorBottom = 0.8;
const double _floorTop = 0.8;
const double _floorBottom = 0.98;

/// Left, ahead and right, as fractions of the picture's width.
const List<(double, double)> _bands = [
  (0.15, 0.4),
  (0.4, 0.6),
  (0.6, 0.85),
];

enum DepthDirection { left, ahead, right }

class DepthReading {
  const DepthReading({
    required this.nearness,
    required this.direction,
    required this.confidence,
  });

  static const DepthReading none = DepthReading(
      nearness: 0, direction: DepthDirection.ahead, confidence: 0);

  /// 0 to 1, in the frame's own range: 1 is as near as anything in it.
  final double nearness;

  final DepthDirection direction;

  /// 0 to 1. Not a probability: nothing here was calibrated.
  final double confidence;

  bool get isBlocked => confidence >= kDepthMinConfidence;

  /// Right in front, and near enough to say stop.
  bool get isUrgent =>
      isBlocked &&
      direction == DepthDirection.ahead &&
      nearness >= kDepthUrgent;
}

/// Reads [inverseDepth] - [side] by [side], row by row from the top, larger
/// nearer - for something standing in the way.
DepthReading depthFrom(Float32List inverseDepth, {int side = kDepthSide}) {
  if (inverseDepth.length < side * side || side < 16) return DepthReading.none;

  // The model's scale and offset change from frame to frame, so everything is
  // read against this frame's own range. Percentiles rather than the extremes,
  // which are a single hot pixel as often as not.
  final sample = <double>[
    for (var row = 0; row < side; row += 3)
      for (var col = 0; col < side; col += 3) inverseDepth[row * side + col],
  ]..sort();
  final low = sample[(sample.length * 0.05).floor()];
  final high = sample[(sample.length * 0.95).floor()];
  final range = high - low;
  if (!range.isFinite || range <= 1e-6) return DepthReading.none;

  // Mean nearness of each band, row by row.
  final profiles = [
    for (final (from, to) in _bands)
      _rowMeans(inverseDepth, side,
          from: (from * side).floor(), to: (to * side).ceil(),
          low: low, range: range),
  ];
  final ahead = profiles[1];

  // The floor line, from the bottom of the picture - in whichever band shows
  // the most floor. Something close enough to fill the bottom of one band
  // flattens that band's line; the floor beside it still recedes.
  final floorFrom = (_floorTop * side).floor();
  final floorTo = (_floorBottom * side).floor();
  var (slope, intercept) = _fit(ahead, floorFrom, floorTo, side);
  for (final band in [profiles[0], profiles[2]]) {
    final (s, i) = _fit(band, floorFrom, floorTo, side);
    if (s > slope) (slope, intercept) = (s, i);
  }
  if (slope < kMinFloorSlope) {
    // No floor rising towards the feet: the bottom of the picture is standing
    // up. Near, and it is something right in front; otherwise it is not
    // known what it is, and nothing is said.
    var sum = 0.0;
    for (var row = floorFrom; row < floorTo; row++) {
      sum += ahead[row];
    }
    final bottom = sum / (floorTo - floorFrom);
    return bottom >= kDepthUrgent
        ? DepthReading(
            nearness: bottom,
            direction: DepthDirection.ahead,
            confidence: kDepthMinConfidence,
          )
        : DepthReading.none;
  }

  // Runs of rows standing above the floor line, in each band.
  final top = (_corridorTop * side).floor();
  final bottom = (_corridorBottom * side).floor();
  final needed = math.max(2, (kBlockedRows * side).round());
  final sure = math.max(needed, (kSureRows * side).round());
  var best = DepthReading.none;
  for (var band = 0; band < profiles.length; band++) {
    final profile = profiles[band];
    var runStart = -1;
    for (var row = top; row <= bottom; row++) {
      final floor = slope * (row / side) + intercept;
      final above = row < bottom && profile[row] - floor >= kAboveFloor;
      if (above) {
        if (runStart < 0) runStart = row;
        continue;
      }
      if (runStart < 0) continue;
      final length = row - runStart;
      if (length >= needed) {
        var margin = 0.0;
        var nearness = 0.0;
        for (var r = runStart; r < row; r++) {
          margin += profile[r] - (slope * (r / side) + intercept);
          nearness += profile[r];
        }
        margin /= length;
        nearness /= length;
        final confidence = (margin / (2 * kAboveFloor)).clamp(0.0, 1.0) *
            (length / sure).clamp(0.0, 1.0);
        final direction = DepthDirection.values[band];
        final better = confidence > best.confidence ||
            (confidence == best.confidence &&
                direction == DepthDirection.ahead);
        if (better) {
          best = DepthReading(
            nearness: nearness.clamp(0.0, 1.0),
            direction: direction,
            confidence: confidence,
          );
        }
      }
      runStart = -1;
    }
  }
  return best;
}

/// The mean of columns [from] to [to] in each row, scaled to the frame's
/// range.
List<double> _rowMeans(Float32List map, int side,
    {required int from,
    required int to,
    required double low,
    required double range}) {
  final width = to - from;
  return [
    for (var row = 0; row < side; row++)
      () {
        var sum = 0.0;
        final base = row * side;
        for (var col = from; col < to; col++) {
          sum += map[base + col];
        }
        return ((sum / width) - low) / range;
      }(),
  ];
}

/// A straight line through [profile] from row [from] to [to]: nearness
/// against height in the picture, 0 at the top and 1 at the bottom.
(double, double) _fit(List<double> profile, int from, int to, int side) {
  var n = 0;
  var sx = 0.0;
  var sy = 0.0;
  var sxx = 0.0;
  var sxy = 0.0;
  for (var row = from; row < to; row++) {
    final x = row / side;
    final y = profile[row];
    n++;
    sx += x;
    sy += y;
    sxx += x * x;
    sxy += x * y;
  }
  final denominator = n * sxx - sx * sx;
  if (n < 2 || denominator.abs() < 1e-12) return (0, sy / math.max(1, n));
  final slope = (n * sxy - sx * sy) / denominator;
  return (slope, (sy - slope * sx) / n);
}
