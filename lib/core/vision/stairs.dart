/// §2.A.3 — stairs, from a model trained to find them.
///
/// YOLO11n in `assets/models/` is trained on COCO, and COCO has no "stairs",
/// so a staircase with nothing nameable in view was "No known objects in
/// view". The first answer was a floor-plane heuristic that looked for
/// regular horizontal banding low in the frame. It was never checked on real
/// photographs, and on the synthetic ones it had, a tiled floor scored 0.86
/// and a zebra crossing 0.75, both over its threshold. It stayed switched off
/// in every tester build, and is gone (PR #74 has its history).
///
/// Stairs now come from a second, single-class YOLO11n, trained on Open
/// Images' "Stairs" boxes with zebra crossings and tiled floors as hard
/// negatives (`tool/fetch_stairs.py`, `tool/train_stairs.sh`), run beside the
/// COCO model the way the face and depth models are. Its boxes join the
/// frame's detections as [kStairsLabel], so everything downstream - ranking
/// against a car, "close" and "very close", the guardian's feed, the journey
/// record - treats stairs as one more object.
///
/// Two things it never claims. Up or down: the training labels do not say,
/// and one camera cannot tell. And metres: nothing here estimates a distance
/// for anything; "close" and "very close" are how big the box is.
///
/// Pure, so the rules are tested without a camera or a model.
library;

import 'dart:typed_data';

import 'detection.dart';
import 'yolo.dart';
import 'yuv_frame.dart';

/// The label stairs are named by, everywhere.
const String kStairsLabel = 'stairs';

/// The stairs model. A build without it runs as before and says nothing
/// about stairs: `StairsDetector.load` returns null.
const String kStairsModelAsset = 'assets/models/yolo11n_stairs.tflite';

/// The side the stairs model was exported at: `[1, 3, 416, 416]` in,
/// `[1, 5, 3549]` out.
const int kStairsSide = 416;

/// Whether the scan screen looks for stairs at all, when the model is there.
/// On by default; `--dart-define=STAIRS_WARNINGS=false` turns it off for a
/// device check of everything else.
const bool kStairsWarnings =
    bool.fromEnvironment('STAIRS_WARNINGS', defaultValue: true);

/// Below this, a stairs box is not mentioned at all.
///
/// The lowest score at which at most 5 percent of photographs with no stairs
/// in them - floors, carpets, walkways, crossings - get a stairs box at all:
/// at 0.35 the first model named stairs on 9 percent of them, at 0.55 on 5
/// (`docs/VISION.md`, "The gate"). Stairs said over every tiled floor would
/// be stairs nobody listens for.
const double kStairsSoft = 0.55;

/// At or above this, stairs close enough to stop for are a "Stop".
///
/// Only once the measurement in `docs/VISION.md`, "Stairs", says the model
/// earns it: recall on close stairs of at least 70 percent, and false alarms
/// on tiled floors, rugs and zebra crossings of at most 5 percent, at this
/// score. The first model found 49 percent. Until then [stairsMayStop] is
/// off and stairs are named, never shouted - a "Stop" for every tiled floor
/// teaches someone to ignore "Stop".
const double kStairsHard = 0.55;

/// Whether stairs may be a "Stop": `--dart-define=STAIRS_STOP=true`, once
/// the gate above has been passed. A variable so tests can say both.
bool stairsMayStop = const bool.fromEnvironment('STAIRS_STOP');

/// The stairs model's input: [frame] fitted into [box], all of red then all
/// of green then all of blue, 0 to 1, grey around it - the layout and
/// padding the COCO model already takes.
void fillLetterboxed(YuvFrame frame, Letterbox box, Float32List out) {
  final side = box.side;
  final plane = side * side;
  out.fillRange(0, 3 * plane, Letterbox.padValue);
  final step = 1 / box.scale;
  for (var row = 0; row < box.drawHeight; row++) {
    final fy = (row + 0.5) * step;
    final at = (row + box.padY) * side + box.padX;
    for (var col = 0; col < box.drawWidth; col++) {
      frame.writeRgb((col + 0.5) * step, fy, out, at + col,
          scale: 1 / 255, shift: 0, stride: plane);
    }
  }
}

/// The stairs in [boxes], as detections of the frame [box] was fitted from.
List<Detection> stairsDetections(List<RawBox> boxes, Letterbox box) => [
      for (final raw in boxes)
        if (raw.score >= kStairsSoft)
          if (_inFrame(raw, box) case final edges?)
            detectionFrom(
              label: kStairsLabel,
              score: raw.score,
              xMin: edges.$1,
              yMin: edges.$2,
              xMax: edges.$3,
              yMax: edges.$4,
            ),
    ];

(double, double, double, double)? _inFrame(RawBox raw, Letterbox box) {
  final xMin = box.toFrameX(raw.left).clamp(0.0, 1.0);
  final xMax = box.toFrameX(raw.right).clamp(0.0, 1.0);
  final yMin = box.toFrameY(raw.top).clamp(0.0, 1.0);
  final yMax = box.toFrameY(raw.bottom).clamp(0.0, 1.0);
  if (xMax <= xMin || yMax <= yMin) return null;
  return (xMin, yMin, xMax, yMax);
}
