import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/blazeface.dart';
import 'package:impairgency/core/vision/face_align.dart';

FacePoint moved(FacePoint p,
    {double scale = 1, double degrees = 0, double tx = 0, double ty = 0}) {
  final r = degrees * math.pi / 180;
  return FacePoint(
    scale * (p.x * math.cos(r) - p.y * math.sin(r)) + tx,
    scale * (p.x * math.sin(r) + p.y * math.cos(r)) + ty,
  );
}

void main() {
  test('the template onto itself is no change', () {
    final fit = fitSimilarity(kFaceTemplate, kFaceTemplate);
    expect(fit.a, closeTo(1, 1e-9));
    expect(fit.b, closeTo(0, 1e-9));
    expect(fit.tx, closeTo(0, 1e-9));
    expect(fit.ty, closeTo(0, 1e-9));
  });

  test('a face tipped 30 degrees, twice the size and off to one side lines up',
      () {
    final seen = [
      for (final p in kFaceTemplate)
        moved(p, scale: 2, degrees: 30, tx: 300, ty: 120)
    ];
    final toCrop = fitSimilarity(seen, kFaceTemplate);
    expect(toCrop.scale, closeTo(0.5, 1e-9));
    expect(toCrop.rotationDegrees, closeTo(-30, 1e-9));
    for (var i = 0; i < seen.length; i++) {
      final lined = toCrop.apply(seen[i]);
      expect(lined.x, closeTo(kFaceTemplate[i].x, 1e-6));
      expect(lined.y, closeTo(kFaceTemplate[i].y, 1e-6));
    }
    // And back: the crop's corner comes from the tipped face.
    final back = toCrop.inverse();
    final corner = back.apply(const FacePoint(0, 0));
    final expected = moved(const FacePoint(0, 0), scale: 2, degrees: 30, tx: 300, ty: 120);
    expect(corner.x, closeTo(expected.x, 1e-6));
    expect(corner.y, closeTo(expected.y, 1e-6));
  });

  test('landmarks that do not quite fit land within a pixel', () {
    final seen = [
      for (final p in kFaceTemplate) moved(p, scale: 1.5, tx: 40, ty: 10)
    ];
    // A nose a pixel out, as a detector's would be.
    seen[2] = FacePoint(seen[2].x + 1, seen[2].y);
    final toCrop = fitSimilarity(seen, kFaceTemplate);
    for (var i = 0; i < seen.length; i++) {
      final lined = toCrop.apply(seen[i]);
      expect((lined.x - kFaceTemplate[i].x).abs(), lessThan(1));
      expect((lined.y - kFaceTemplate[i].y).abs(), lessThan(1));
    }
  });

  test("a detector's face, from fractions of its square to the crop", () {
    const square = 224.0;
    final landmarks = [
      for (final p in kFaceTemplate) FacePoint(p.x * 2 / square, p.y * 2 / square),
      const FacePoint(0.1, 0.5),
      const FacePoint(0.9, 0.5),
    ];
    final face = FaceBox(
        centerX: 0.5, centerY: 0.5, width: 0.8, height: 0.8, score: 0.9, landmarks: landmarks);
    final toCrop = alignFace(face, (p) => FacePoint(100 + p.x * square, 50 + p.y * square));
    final eye = toCrop.apply(FacePoint(100 + landmarks[0].x * square, 50 + landmarks[0].y * square));
    expect(eye.x, closeTo(kFaceTemplate[0].x, 1e-6));
    expect(eye.y, closeTo(kFaceTemplate[0].y, 1e-6));
  });

  test('points that are all in one place cannot be fitted', () {
    const p = FacePoint(1, 1);
    expect(() => fitSimilarity(const [p, p], kFaceTemplate.take(2).toList()),
        throwsArgumentError);
  });
}
