/// Finding faces: MediaPipe's BlazeFace, short range, read in Dart.
///
/// The model sees a 128 by 128 picture and answers for 896 fixed anchor
/// points at once - a box and six landmarks each, and a score. Nothing in it
/// thresholds, decodes or de-duplicates; MediaPipe does that in C++ graphs this
/// app does not ship. So it is done here, with MediaPipe's own settings for
/// this model written out beside the code that uses them, where a test can
/// hold them still.
///
/// Pure, like `yolo.dart`: every mistake here is a face found where there is
/// none, or a friend's eyes swapped for their ears, and none of them crash.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Side of the square the model looks at.
const int kBlazeFaceSide = 128;

/// Anchors, boxes and landmarks the short-range model answers with.
const int kBlazeFaceAnchors = 896;
const int kBlazeFaceCoords = 16;
const int kBlazeFaceKeypoints = 6;

/// MediaPipe's own score threshold for this model.
const double kBlazeFaceMinScore = 0.5;

/// MediaPipe's own overlap for merging one face's several boxes.
const double kBlazeFaceMergeIou = 0.3;

/// Which landmark is which. "Right" is the person's right, which is on the
/// left of a picture taken of them.
enum FaceLandmark { rightEye, leftEye, noseTip, mouth, rightEar, leftEar }

class FacePoint {
  const FacePoint(this.x, this.y);
  final double x;
  final double y;

  @override
  String toString() => 'FacePoint(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// One face, in fractions of the picture the model saw: 0 to 1 across and
/// down.
class FaceBox {
  const FaceBox({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.score,
    required this.landmarks,
  });

  final double centerX;
  final double centerY;
  final double width;
  final double height;
  final double score;

  /// In [FaceLandmark] order.
  final List<FacePoint> landmarks;

  double get left => centerX - width / 2;
  double get top => centerY - height / 2;
  double get right => centerX + width / 2;
  double get bottom => centerY + height / 2;

  FacePoint landmark(FaceLandmark which) => landmarks[which.index];

  /// How far the line between the eyes leans, in degrees. A face tipped far
  /// over is a poor sample of what it looks like upright.
  double get rollDegrees {
    final right = landmark(FaceLandmark.rightEye);
    final left = landmark(FaceLandmark.leftEye);
    return math.atan2(left.y - right.y, left.x - right.x) * 180 / math.pi;
  }
}

class _Anchor {
  const _Anchor(this.x, this.y);
  final double x;
  final double y;
}

/// The 896 anchor centres, in MediaPipe's order.
///
/// From its SSD anchor settings for this model: strides 8, 16, 16 and 16 on a
/// 128 input, one aspect ratio plus one interpolated scale - so two anchors per
/// cell per layer - and a fixed anchor size, so every anchor is 1 by 1 and
/// only its centre matters. Layers that share a stride share a grid: 16 by 16
/// cells with 2 anchors, then 8 by 8 with 6. 512 and 384.
final List<_Anchor> _anchors = () {
  const strides = [8, 16, 16, 16];
  final anchors = <_Anchor>[];
  var layer = 0;
  while (layer < strides.length) {
    var perCell = 0;
    var last = layer;
    while (last < strides.length && strides[last] == strides[layer]) {
      perCell += 2;
      last++;
    }
    final cells = (kBlazeFaceSide / strides[layer]).ceil();
    for (var y = 0; y < cells; y++) {
      for (var x = 0; x < cells; x++) {
        for (var i = 0; i < perCell; i++) {
          anchors.add(_Anchor((x + 0.5) / cells, (y + 0.5) / cells));
        }
      }
    }
    layer = last;
  }
  return anchors;
}();

/// How many anchors there are, for a check against the loaded model.
int get blazeFaceAnchorCount => _anchors.length;

/// Faces in one run of the model.
///
/// [regressors] is `[1, 896, 16]` flattened: per anchor, the box as centre x,
/// centre y, width and height, then six landmarks as x, y - all in pixels of
/// the 128 input, and the centre and landmarks relative to the anchor.
/// [scores] is `[1, 896, 1]`, before the sigmoid.
List<FaceBox> decodeBlazeFace(
  Float32List regressors,
  Float32List scores, {
  double minScore = kBlazeFaceMinScore,
  double mergeIou = kBlazeFaceMergeIou,
}) {
  final anchors = _anchors.length;
  if (regressors.length < anchors * kBlazeFaceCoords ||
      scores.length < anchors) {
    throw ArgumentError('BlazeFace output is ${regressors.length} and '
        '${scores.length} floats; $anchors anchors need '
        '${anchors * kBlazeFaceCoords} and $anchors.');
  }

  final found = <FaceBox>[];
  for (var i = 0; i < anchors; i++) {
    // Clipped as MediaPipe clips it, so a wild logit cannot overflow.
    final logit = scores[i].clamp(-100.0, 100.0);
    final score = 1 / (1 + math.exp(-logit));
    if (score < minScore) continue;

    final anchor = _anchors[i];
    final at = i * kBlazeFaceCoords;
    found.add(FaceBox(
      centerX: regressors[at] / kBlazeFaceSide + anchor.x,
      centerY: regressors[at + 1] / kBlazeFaceSide + anchor.y,
      width: regressors[at + 2] / kBlazeFaceSide,
      height: regressors[at + 3] / kBlazeFaceSide,
      score: score,
      landmarks: [
        for (var k = 0; k < kBlazeFaceKeypoints; k++)
          FacePoint(
            regressors[at + 4 + 2 * k] / kBlazeFaceSide + anchor.x,
            regressors[at + 5 + 2 * k] / kBlazeFaceSide + anchor.y,
          ),
      ],
    ));
  }
  return mergeFaces(found, iou: mergeIou);
}

/// MediaPipe's weighted suppression: every box that overlaps the strongest by
/// more than [iou] is folded into it, each counting by its score.
///
/// One face lights up several neighbouring anchors. Keeping only the best
/// one, as ordinary suppression does, throws away the others' opinion of
/// where the eyes are - and the eyes decide how the face is lined up for
/// recognising, which is the whole use of finding it.
List<FaceBox> mergeFaces(List<FaceBox> faces, {double iou = kBlazeFaceMergeIou}) {
  final remaining = [...faces]..sort((a, b) => b.score.compareTo(a.score));
  final merged = <FaceBox>[];
  while (remaining.isNotEmpty) {
    final best = remaining.first;
    final group = <FaceBox>[];
    remaining.removeWhere((face) {
      if (identical(face, best) || _iou(face, best) > iou) {
        group.add(face);
        return true;
      }
      return false;
    });

    var total = 0.0;
    var cx = 0.0, cy = 0.0, w = 0.0, h = 0.0;
    final lx = List<double>.filled(kBlazeFaceKeypoints, 0);
    final ly = List<double>.filled(kBlazeFaceKeypoints, 0);
    for (final face in group) {
      final weight = face.score;
      total += weight;
      cx += face.centerX * weight;
      cy += face.centerY * weight;
      w += face.width * weight;
      h += face.height * weight;
      for (var k = 0; k < kBlazeFaceKeypoints; k++) {
        lx[k] += face.landmarks[k].x * weight;
        ly[k] += face.landmarks[k].y * weight;
      }
    }
    merged.add(FaceBox(
      centerX: cx / total,
      centerY: cy / total,
      width: w / total,
      height: h / total,
      score: best.score,
      landmarks: [
        for (var k = 0; k < kBlazeFaceKeypoints; k++)
          FacePoint(lx[k] / total, ly[k] / total),
      ],
    ));
  }
  return merged;
}

double _iou(FaceBox a, FaceBox b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (w <= 0 || h <= 0) return 0;
  final overlap = w * h;
  final union = a.width * a.height + b.width * b.height - overlap;
  return union <= 0 ? 0 : overlap / union;
}
