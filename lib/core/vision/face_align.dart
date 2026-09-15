/// Lining a face up the way the recogniser learned faces.
///
/// MobileFaceNet was trained on 112 by 112 crops with the eyes, nose and mouth
/// in the same places every time - the ArcFace template below. A face cropped
/// any other way, a little tilted, a little off-centre, gives numbers that
/// drift from the same person's straight-on numbers far more than two
/// different people's do. So before a face is recognised it is turned, scaled
/// and moved until its landmarks sit on the template, as nearly as one
/// rotation, one scale and one shift allow.
///
/// Pure: the fit is arithmetic on four points, tested to the pixel.
library;

import 'dart:math' as math;

import 'blazeface.dart';

/// Side of the recogniser's square input.
const int kFaceCropSide = 112;

/// Where the landmarks go in that square: ArcFace's template, with its two
/// mouth corners averaged into the one mouth point BlazeFace gives. The eye on
/// the left of the picture is the person's right eye.
const List<FacePoint> kFaceTemplate = [
  FacePoint(38.2946, 51.6963), // right eye
  FacePoint(73.5318, 51.5014), // left eye
  FacePoint(56.0252, 71.7366), // nose tip
  FacePoint(56.1396, 92.2848), // mouth
];

/// A rotation, a uniform scale and a shift: `x' = a x - b y + tx`,
/// `y' = b x + a y + ty`.
class Similarity {
  const Similarity(this.a, this.b, this.tx, this.ty);

  final double a;
  final double b;
  final double tx;
  final double ty;

  FacePoint apply(FacePoint p) =>
      FacePoint(a * p.x - b * p.y + tx, b * p.x + a * p.y + ty);

  /// The transform back: for each pixel of the crop, where in the picture to
  /// read it from.
  Similarity inverse() {
    final d = a * a + b * b;
    if (d == 0) throw StateError('A transform with no scale has no inverse.');
    final ia = a / d;
    final ib = -b / d;
    return Similarity(ia, ib, -(ia * tx - ib * ty), -(ib * tx + ia * ty));
  }

  double get scale => math.sqrt(a * a + b * b);
  double get rotationDegrees => math.atan2(b, a) * 180 / math.pi;
}

/// The least-squares similarity taking [from] onto [to], point for point.
Similarity fitSimilarity(List<FacePoint> from, List<FacePoint> to) {
  if (from.length != to.length || from.length < 2) {
    throw ArgumentError('Need two or more matching points.');
  }
  final n = from.length;
  var fx = 0.0, fy = 0.0, gx = 0.0, gy = 0.0;
  for (var i = 0; i < n; i++) {
    fx += from[i].x;
    fy += from[i].y;
    gx += to[i].x;
    gy += to[i].y;
  }
  fx /= n;
  fy /= n;
  gx /= n;
  gy /= n;

  var dot = 0.0, cross = 0.0, norm = 0.0;
  for (var i = 0; i < n; i++) {
    final px = from[i].x - fx;
    final py = from[i].y - fy;
    final qx = to[i].x - gx;
    final qy = to[i].y - gy;
    dot += px * qx + py * qy;
    cross += px * qy - py * qx;
    norm += px * px + py * py;
  }
  if (norm == 0) throw ArgumentError('The points are all in one place.');
  final a = dot / norm;
  final b = cross / norm;
  return Similarity(a, b, gx - (a * fx - b * fy), gy - (b * fx + a * fy));
}

/// The transform from a face's landmarks, in pixels of the picture, to the
/// crop the recogniser takes.
///
/// [toPixels] turns the model's fractions into picture pixels - the face was
/// found in a crop of the frame, and the crop has to be undone first.
Similarity alignFace(FaceBox face, FacePoint Function(FacePoint) toPixels) =>
    fitSimilarity([
      toPixels(face.landmark(FaceLandmark.rightEye)),
      toPixels(face.landmark(FaceLandmark.leftEye)),
      toPixels(face.landmark(FaceLandmark.noseTip)),
      toPixels(face.landmark(FaceLandmark.mouth)),
    ], kFaceTemplate);
