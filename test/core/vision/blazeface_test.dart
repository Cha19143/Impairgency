import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/blazeface.dart';

/// All 896 anchors below the threshold, until a test lights some up.
(Float32List, Float32List) quietOutput() {
  final regressors = Float32List(kBlazeFaceAnchors * kBlazeFaceCoords);
  final scores = Float32List(kBlazeFaceAnchors)..fillRange(0, kBlazeFaceAnchors, -10);
  return (regressors, scores);
}

/// Index of anchor [i] in cell ([x], [y]) of the 8 by 8 grid.
int coarse(int x, int y, [int i = 0]) => 512 + (y * 8 + x) * 6 + i;

void light(Float32List regressors, Float32List scores, int anchor,
    {double logit = 3,
    double dx = 0,
    double dy = 0,
    double w = 64,
    double h = 64,
    List<double> landmarks = const [-16, -10, 16, -10, 0, 4, 0, 20, -30, -6, 30, -6]}) {
  scores[anchor] = logit;
  final at = anchor * kBlazeFaceCoords;
  regressors[at] = dx;
  regressors[at + 1] = dy;
  regressors[at + 2] = w;
  regressors[at + 3] = h;
  for (var k = 0; k < landmarks.length; k++) {
    regressors[at + 4 + k] = landmarks[k];
  }
}

void main() {
  test('896 anchors: 16 by 16 cells of 2, then 8 by 8 cells of 6', () {
    expect(blazeFaceAnchorCount, 896);
  });

  test('nothing above the threshold is no faces', () {
    final (regressors, scores) = quietOutput();
    expect(decodeBlazeFace(regressors, scores), isEmpty);
  });

  test('a face: its box and landmarks, relative to its anchor', () {
    final (regressors, scores) = quietOutput();
    light(regressors, scores, coarse(3, 3));
    final faces = decodeBlazeFace(regressors, scores);
    expect(faces, hasLength(1));
    final face = faces.single;
    // Cell (3, 3) of 8 is centred at 3.5 / 8.
    expect(face.centerX, closeTo(0.4375, 1e-6));
    expect(face.centerY, closeTo(0.4375, 1e-6));
    expect(face.width, closeTo(0.5, 1e-6));
    expect(face.score, closeTo(0.9526, 1e-3));
    final rightEye = face.landmark(FaceLandmark.rightEye);
    expect(rightEye.x, closeTo(0.4375 - 16 / 128, 1e-6));
    expect(rightEye.y, closeTo(0.4375 - 10 / 128, 1e-6));
    expect(face.landmark(FaceLandmark.mouth).y, closeTo(0.4375 + 20 / 128, 1e-6));
    expect(face.rollDegrees, closeTo(0, 1e-6));
  });

  test('the fine grid comes first, two anchors a cell', () {
    final (regressors, scores) = quietOutput();
    // Cell (1, 0) of 16, second anchor: index 3.
    light(regressors, scores, 3, w: 16, h: 16);
    final face = decodeBlazeFace(regressors, scores).single;
    expect(face.centerX, closeTo(1.5 / 16, 1e-6));
    expect(face.centerY, closeTo(0.5 / 16, 1e-6));
  });

  test("one face's several boxes are merged, weighted by score", () {
    final (regressors, scores) = quietOutput();
    light(regressors, scores, coarse(3, 3), logit: 3, dx: 0);
    light(regressors, scores, coarse(3, 3, 1), logit: 0.5, dx: 8);
    final faces = decodeBlazeFace(regressors, scores);
    expect(faces, hasLength(1));
    final strong = 1 / (1 + 0.0497870684); // sigmoid(3)
    final weak = 0.6224593312; // sigmoid(0.5)
    final expected = (0.4375 * strong + (0.4375 + 8 / 128) * weak) / (strong + weak);
    expect(faces.single.centerX, closeTo(expected, 1e-4));
    expect(faces.single.score, closeTo(strong, 1e-4));
  });

  test('two faces apart stay two', () {
    final (regressors, scores) = quietOutput();
    light(regressors, scores, coarse(1, 3), w: 24, h: 24);
    light(regressors, scores, coarse(6, 3), w: 24, h: 24);
    expect(decodeBlazeFace(regressors, scores), hasLength(2));
  });

  test('a tipped head has a roll', () {
    const face = FaceBox(
      centerX: 0.5,
      centerY: 0.5,
      width: 0.4,
      height: 0.4,
      score: 0.9,
      landmarks: [
        FacePoint(0.4, 0.4),
        FacePoint(0.6, 0.5),
        FacePoint(0.5, 0.5),
        FacePoint(0.5, 0.6),
        FacePoint(0.3, 0.45),
        FacePoint(0.7, 0.55),
      ],
    );
    expect(face.rollDegrees, closeTo(26.565, 1e-2));
  });

  test('output of the wrong size is refused, not misread', () {
    expect(() => decodeBlazeFace(Float32List(10), Float32List(896)),
        throwsArgumentError);
  });
}
