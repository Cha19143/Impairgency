/// §2.A.3 — the fall risk the object model has no class for.
///
/// YOLO11n in `assets/models/` is trained on COCO, and COCO has no "stairs".
/// Training one would need labelled photographs of the stairs these users
/// actually walk down, and nobody has labelled them. So this is the other
/// option `docs/SCOPE.md` named: a floor-plane heuristic, with a confidence
/// threshold that stays silent rather than guessing.
///
/// **What it actually detects is regular horizontal banding low in the frame.**
/// That is what a flight of stairs looks like to one camera. It is also what an
/// escalator, a zebra crossing and a striped rug look like - and, measured when
/// this was ported from PR #74, a tiled floor: evenly receding grout lines score
/// 0.86 and a zebra crossing 0.75, both over the threshold. Seen from above, a
/// flight is a row of nosing edges, and so is a floor of tiles; banding alone
/// cannot tell them apart. That is why [kStairsWarnings] is off until the
/// heuristic has been checked on real stairs and real floors.
///
/// It never claims a direction. Ascending and descending stairs produce the same
/// banding, and a single camera has no depth with which to tell them apart, so
/// the app says "stairs" and leaves the rest to the person holding the phone.
///
/// Pure, and takes a plain grid, so every case below is a test rather than a
/// walk to a stairwell. [fillStairsGrid] builds the grid from a camera frame.
library;

import 'dart:math' as math;

import 'yuv_frame.dart';

/// Whether the scan screen looks for stairs and warns about them.
///
/// Off unless a build asks for it with `--dart-define=STAIRS_WARNINGS=true`.
/// A warning that says "Stop" on every tiled floor in a mall teaches someone to
/// ignore "Stop", and the next one may be a car. Turn it on for a device check
/// against real stairs and real floors - see `docs/VISION.md`, "Stairs" - and
/// make it the default only when that check says it earns it.
const bool kStairsWarnings = bool.fromEnvironment('STAIRS_WARNINGS');

/// Side of the brightness grid the heuristic reads: the size its thresholds
/// were tuned at. Tread spacing is measured in grid rows, so a smaller grid
/// would merge treads these tests separate.
const int kStairsGridSide = 300;

/// Treads needed before a pattern is a flight rather than a step.
///
/// One strong horizontal edge is a threshold strip, a shadow, or the join
/// between a rug and a floor. Three could be a coincidence of furniture. Four
/// evenly spaced is a staircase.
const int kMinTreads = 4;

/// Spacing below which two treads are no longer separable.
///
/// Perspective packs the far end of a flight into a handful of rows, where the
/// gap between one nosing and the next is quantised to two or three pixels and
/// carries no information about whether they are evenly spaced. Those rows are
/// not the ones you are about to step on either, so the search stops before
/// them.
const int kMinTreadGap = 4;

/// Below this, say nothing at all.
///
/// The requirement is silence rather than a guess, so this is a floor on
/// *speaking*, not a tie-breaker between two things to say.
const double kStairsMinConfidence = 0.6;

/// Where in the frame to look.
///
/// The floor is below the horizon. Searching the whole image finds the banding
/// in venetian blinds, bookshelves and radiators, none of which are underfoot.
const double _regionTop = 0.45;
const double _regionSide = 0.15;

/// Fills the part of [grid] that [stairsFrom] reads with the brightness of
/// [frame], turned upright and stretched to the grid, as the heuristic was
/// tested.
///
/// Only the searched region - the lower 55% of the frame, 15% in from each
/// side - is sampled; the rest of the grid is never read. Nearest pixel, from
/// the brightness plane alone.
void fillStairsGrid(YuvFrame frame, List<List<int>> grid) {
  final height = grid.length;
  if (height == 0) return;
  final width = grid.first.length;
  final top = (height * _regionTop).floor();
  final left = (width * _regionSide).floor();
  final right = width - left;
  final stepX = frame.uprightWidth / width;
  final stepY = frame.uprightHeight / height;
  for (var y = top; y < height; y++) {
    final row = grid[y];
    final fy = (y + 0.5) * stepY;
    for (var x = left; x < right; x++) {
      row[x] = frame.lumaAt((x + 0.5) * stepX, fy);
    }
  }
}

class StairsReading {
  const StairsReading({
    required this.confidence,
    required this.treads,
    required this.spacingRegularity,
  });

  static const StairsReading none =
      StairsReading(confidence: 0, treads: 0, spacingRegularity: 0);

  /// 0 to 1. Not a probability — nothing here was calibrated against labelled
  /// ground truth, and calling it one would be the invented-accuracy defect
  /// this project was rebuilt to avoid.
  final double confidence;

  final int treads;

  /// How evenly spaced the edges are, 0 to 1. The part that separates a
  /// staircase from clutter that happens to have edges in it.
  final double spacingRegularity;

  bool get isStairs => confidence >= kStairsMinConfidence;
}

/// Looks for a staircase in one frame.
///
/// [luma] is brightness only, rows top to bottom. Colour is no help here and
/// costs three times the arithmetic on every frame.
StairsReading stairsFrom(
  List<List<int>> luma, {
  int minTreads = kMinTreads,
}) {
  final height = luma.length;
  if (height < 24) return StairsReading.none;
  final width = luma.first.length;
  if (width < 16) return StairsReading.none;

  final top = (height * _regionTop).floor();
  final left = (width * _regionSide).floor();
  final right = width - left;
  if (right - left < 8 || height - top < 12) return StairsReading.none;

  // A profile of horizontal-edge strength, one value per row.
  //
  // Vertical stripes - railings, door frames, blinds - produce identical
  // consecutive rows and therefore a flat profile. They fall out here rather
  // than needing a rule of their own.
  final profile = <double>[];
  final span = <double>[];
  for (var y = top; y < height - 1; y++) {
    final row = luma[y];
    final next = luma[y + 1];
    var sum = 0.0;
    var strong = 0;
    for (var x = left; x < right; x++) {
      final delta = (next[x] - row[x]).abs();
      sum += delta;
      if (delta >= 18) strong++;
    }
    final count = right - left;
    profile.add(sum / count);
    // How much of the width this edge crosses. A stair nosing runs the width of
    // the staircase; a table leg does not.
    span.add(strong / count);
  }

  final peaks = _peaks(profile);
  if (peaks.length < minTreads) {
    return StairsReading(
      confidence: 0,
      treads: peaks.length,
      spacingRegularity: 0,
    );
  }

  final near = _nearField(peaks);
  if (near.length < minTreads) {
    return StairsReading(
      confidence: 0,
      treads: near.length,
      spacingRegularity: 0,
    );
  }

  // [near] runs from the bottom of the frame upwards, so each gap is the
  // distance from one tread to the one behind it.
  final regularity = _regularity([
    for (var i = 1; i < near.length; i++) (near[i - 1] - near[i]).toDouble(),
  ]);

  final meanSpan =
      near.map((i) => span[i]).reduce((a, b) => a + b) / near.length;

  // Four treads is already a staircase, so the count contributes a high floor
  // rather than scaling from zero; more treads is more certain, but not much.
  final treadFactor =
      math.min(1.0, 0.78 + 0.06 * (near.length - minTreads));

  final confidence =
      (treadFactor * regularity * math.min(1.0, meanSpan / 0.55))
          .clamp(0.0, 1.0);

  return StairsReading(
    confidence: confidence,
    treads: near.length,
    spacingRegularity: regularity,
  );
}

/// Rows that stand out as edges, thinned so one thick edge counts once.
List<int> _peaks(List<double> profile) {
  final mean = profile.reduce((a, b) => a + b) / profile.length;
  final variance = profile
          .map((v) => (v - mean) * (v - mean))
          .reduce((a, b) => a + b) /
      profile.length;
  final deviation = math.sqrt(variance);
  final peak = profile.reduce(math.max);

  // A flat profile has no edges in it, however the numbers are scaled. Without
  // this, gentle noise on a blank wall produces "peaks" at its own mean.
  if (peak < 6 || deviation < 1.5) return const [];

  final floor = math.max(mean + deviation * 0.7, peak * 0.35);

  final found = <int>[];
  for (var i = 1; i < profile.length - 1; i++) {
    if (profile[i] < floor) continue;
    if (profile[i] < profile[i - 1] || profile[i] < profile[i + 1]) continue;
    // A nosing two or three rows thick would otherwise be three treads.
    if (found.isNotEmpty && i - found.last < 3) {
      if (profile[i] > profile[found.last]) found[found.length - 1] = i;
      continue;
    }
    found.add(i);
  }
  return found;
}

/// How regular a run of gaps is, 0 to 1.
///
/// Measured on the **ratio** between one gap and the next, not on the gaps
/// themselves. This is the correction that made the heuristic work at all.
///
/// Perspective shrinks each successive tread's spacing by a roughly constant
/// factor as the flight recedes, so a real staircase is regular in ratio while
/// being wildly irregular in absolute size. Judged on the raw gaps - one minus
/// their coefficient of variation - a staircase rendered from a pinhole camera
/// model scored 0.38 against a threshold of 0.6, and no real
/// flight could ever have been announced. The same flight scores 0.87 here.
///
/// Evenly spaced bands are the special case where every ratio is one, so a
/// flat pattern still scores perfectly; and clutter, whose gaps jump around,
/// scores lower than it did before.
double _regularity(List<double> gaps) {
  if (gaps.length < 2) return 0;
  final ratios = <double>[];
  for (var i = 1; i < gaps.length; i++) {
    if (gaps[i - 1] <= 0) return 0;
    ratios.add(gaps[i] / gaps[i - 1]);
  }

  final mean = ratios.reduce((a, b) => a + b) / ratios.length;
  if (mean <= 0) return 0;
  final variance =
      ratios.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) /
          ratios.length;
  final cv = math.sqrt(variance) / mean;
  return (1.0 - cv).clamp(0.0, 1.0);
}

/// The treads near enough to be worth measuring, nearest first.
///
/// Walks up from the bottom of the frame and stops as soon as the treads stop
/// being separable, so that the unresolvable far end of a flight cannot drown
/// out the few steps actually in front of the user's feet.
List<int> _nearField(List<int> peaks) {
  final near = <int>[peaks.last];
  for (var i = peaks.length - 2; i >= 0; i--) {
    if (near.last - peaks[i] < kMinTreadGap) break;
    near.add(peaks[i]);
  }
  return near;
}
