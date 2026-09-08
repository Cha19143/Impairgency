/// Turning YOLO11's one output tensor into boxes.
///
/// The model does none of this itself. An SSD graph ends in a
/// TFLite_Detection_PostProcess node and hands back four tidy tensors —
/// boxes, classes, scores, a count — already thresholded and already
/// de-duplicated. YOLO11 ends at the head: one tensor, every anchor it has,
/// no threshold and no non-maximum suppression. All of that is here.
///
/// Which is the reason this file is in `core/` with no Flutter and no FFI in
/// sight. Every mistake worth making lives in this arithmetic — a transposed
/// index, a centre read as a corner, suppression that keeps the wrong box —
/// and none of them crash. They mis-describe the room to someone who cannot
/// check. So they are unit tested against hand-built tensors instead.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// One box as the model gives it: normalised to the square input it was fed,
/// centre and size rather than corners, and one class rather than a vector.
class RawBox {
  const RawBox({
    required this.classIndex,
    required this.score,
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
  });

  final int classIndex;
  final double score;
  final double centerX;
  final double centerY;
  final double width;
  final double height;

  double get left => centerX - width / 2;
  double get top => centerY - height / 2;
  double get right => centerX + width / 2;
  double get bottom => centerY + height / 2;

  double get area => math.max(0.0, width) * math.max(0.0, height);
}

/// The four box rows at the top of the output tensor, before the classes.
const int kBoxRows = 4;

/// COCO, which is what the shipped weights were trained on.
const int kYoloClasses = 80;

/// Overlap above which two boxes are treated as one object.
///
/// Ultralytics' own default. Left there rather than tuned by eye, because
/// tuning it against a handful of scenes is how a threshold ends up fitted to
/// the developer's living room.
const double kNmsIou = 0.45;

/// Enough for any scene worth describing. Guidance names one object and
/// sometimes a second, so a cap this high only exists to bound the work.
const int kMaxBoxes = 20;

/// Reads `[1, 4 + classes, anchors]` into boxes worth keeping.
///
/// The tensor is laid out by *row*: all 2100 centre-x values, then all 2100
/// centre-y, and so on. Element `(row, anchor)` is therefore at
/// `row * anchors + anchor`, and reading it the other way round — the mistake
/// that shape invites — produces boxes that are individually plausible and
/// collectively nonsense.
///
/// Scores arrive already through a sigmoid, one per class per anchor, and are
/// not multiplied by any objectness term: YOLO has not had a separate
/// objectness output since v8. The class score is the confidence.
List<RawBox> decodeYolo(
  Float32List output, {
  required int anchors,
  int classes = kYoloClasses,
  required double minScore,
  double iou = kNmsIou,
  int maxBoxes = kMaxBoxes,
}) {
  final expected = (kBoxRows + classes) * anchors;
  if (output.length < expected) {
    throw ArgumentError(
      'Output holds ${output.length} floats; '
      '$anchors anchors x ${kBoxRows + classes} rows needs $expected.',
    );
  }

  final kept = <RawBox>[];
  for (var anchor = 0; anchor < anchors; anchor++) {
    // The best class for this anchor, found without materialising the other
    // 79. At 2100 anchors this loop runs 168,000 times per frame, on the same
    // thread that draws the screen.
    var bestClass = 0;
    var bestScore = output[kBoxRows * anchors + anchor];
    for (var c = 1; c < classes; c++) {
      final score = output[(kBoxRows + c) * anchors + anchor];
      if (score > bestScore) {
        bestScore = score;
        bestClass = c;
      }
    }
    // At the threshold is not below it. `kMinScore` is documented as the
    // confidence below which a detection is noise, and `guidanceFor` reads it
    // the same way; a decoder that used `>` here would drop a box the layer
    // above would have kept.
    if (bestScore < minScore) continue;

    kept.add(RawBox(
      classIndex: bestClass,
      score: bestScore,
      centerX: output[anchor],
      centerY: output[anchors + anchor],
      width: output[2 * anchors + anchor],
      height: output[3 * anchors + anchor],
    ));
  }

  return suppressOverlaps(kept, iou: iou, maxBoxes: maxBoxes);
}

/// Non-maximum suppression, deliberately class-agnostic.
///
/// Ultralytics suppresses within a class and lets two labels sit on one
/// object, which is right for counting things and wrong for talking. A chair
/// that the model also half-believes is a bench is one thing to walk into, and
/// guidance would otherwise announce it twice — "Stop. chair right in front of
/// you. bench ahead" — for a single obstacle.
///
/// It costs little: suppression needs [iou] overlap, and a person standing in
/// front of a bus overlaps it by their own area over the bus's, which is
/// nowhere near 0.45. Small things in front of big things survive, which is
/// the case that matters.
List<RawBox> suppressOverlaps(
  List<RawBox> boxes, {
  double iou = kNmsIou,
  int maxBoxes = kMaxBoxes,
}) {
  final ordered = [...boxes]..sort((a, b) => b.score.compareTo(a.score));
  final kept = <RawBox>[];
  for (final box in ordered) {
    if (kept.length >= maxBoxes) break;
    var covered = false;
    for (final winner in kept) {
      if (intersectionOverUnion(box, winner) > iou) {
        covered = true;
        break;
      }
    }
    if (!covered) kept.add(box);
  }
  return kept;
}

/// Shared area over combined area, and zero when they do not touch.
double intersectionOverUnion(RawBox a, RawBox b) {
  final overlapWidth = math.min(a.right, b.right) - math.max(a.left, b.left);
  final overlapHeight = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (overlapWidth <= 0 || overlapHeight <= 0) return 0;

  final overlap = overlapWidth * overlapHeight;
  final union = a.area + b.area - overlap;
  return union <= 0 ? 0 : overlap / union;
}

/// How a camera frame was fitted into the model's square input.
///
/// The frame is scaled to fit whole and centred, with grey where it does not
/// reach — rather than stretched to the corners, which is what the SSD version
/// did and what is easier.
///
/// Stretching is not a neutral choice here. It leaves *direction* intact,
/// because the squeeze is linear, but it inflates whatever axis was shorter —
/// and [Detection.extent] is the app's only depth cue, so on a 4:3 frame every
/// horizontal box comes out a third nearer than it is. "Stop, right in front
/// of you" for something across the room is exactly the failure the safety
/// notice promises the app does not commit.
class Letterbox {
  Letterbox({
    required this.frameWidth,
    required this.frameHeight,
    required this.side,
  })  : assert(frameWidth > 0 && frameHeight > 0 && side > 0),
        scale = math.min(side / frameWidth, side / frameHeight) {
    drawWidth = (frameWidth * scale).round().clamp(1, side);
    drawHeight = (frameHeight * scale).round().clamp(1, side);
    padX = (side - drawWidth) ~/ 2;
    padY = (side - drawHeight) ~/ 2;
  }

  final int frameWidth;
  final int frameHeight;

  /// Side of the model's square input, in pixels.
  final int side;

  /// Frame pixels to input pixels.
  final double scale;

  late final int drawWidth;
  late final int drawHeight;
  late final int padX;
  late final int padY;

  /// What YOLO's own letterbox pads with, as the model wants it: 0 to 1.
  static const double padValue = 114 / 255;

  /// A model-space x, 0 to 1, as a fraction of the frame the camera saw.
  ///
  /// Undoing the padding matters as much as undoing the scale. Skip it and
  /// every direction is dragged towards centre, so an obstacle at the very
  /// edge of the frame is announced as "ahead".
  double toFrameX(double x) => (x * side - padX) / drawWidth;

  double toFrameY(double y) => (y * side - padY) / drawHeight;
}
