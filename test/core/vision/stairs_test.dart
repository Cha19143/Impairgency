import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/stairs.dart';
import 'package:impairgency/core/vision/yolo.dart';
import 'package:impairgency/core/vision/yuv_frame.dart';

/// A grey frame, brightness [luma] everywhere.
YuvFrame grey({int width = 8, int height = 4, int luma = 200}) {
  final uv = Uint8List((width ~/ 2) * (height ~/ 2))
    ..fillRange(0, (width ~/ 2) * (height ~/ 2), 128);
  return YuvFrame(
    width: width,
    height: height,
    y: Uint8List(width * height)..fillRange(0, width * height, luma),
    u: uv,
    v: Uint8List.fromList(uv),
    yRowStride: width,
    uvRowStride: width ~/ 2,
    uvPixelStride: 1,
    biPlanar: false,
    sensorOrientation: 0,
  );
}

void main() {
  group("the stairs model's input", () {
    test('the frame fitted in, planar, padded with grey', () {
      // An 8 by 4 frame in an 8 by 8 square: two rows of padding above and
      // below, all of red then green then blue - the COCO model's layout.
      final box = Letterbox(frameWidth: 8, frameHeight: 4, side: 8);
      final out = Float32List(3 * 64);
      fillLetterboxed(grey(), box, out);

      expect(box.padY, 2);
      expect(out[0], closeTo(Letterbox.padValue, 1e-6),
          reason: 'red, top padding');
      expect(out[2 * 8 + 3], closeTo(200 / 255, 1e-6), reason: 'red, inside');
      expect(out[64 + 2 * 8 + 3], closeTo(200 / 255, 1e-6),
          reason: 'green, a plane on');
      expect(out[128 + 7 * 8], closeTo(Letterbox.padValue, 1e-6),
          reason: 'blue, bottom');
    });
  });

  group('boxes back into the frame', () {
    final box = Letterbox(frameWidth: 8, frameHeight: 4, side: 8);

    RawBox raw({double score = 0.8}) => RawBox(
          classIndex: 0,
          score: score,
          centerX: 0.5,
          centerY: 0.5,
          width: 0.5,
          height: 0.25,
        );

    test('a box in the padded square is a box of what the camera saw', () {
      final found = stairsDetections([raw()], box);
      final d = found.single;
      expect(d.label, kStairsLabel);
      expect(d.box!.left, closeTo(0.25, 1e-6));
      expect(d.box!.top, closeTo(0.25, 1e-6),
          reason: 'the padding rows are not the frame');
      expect(d.box!.bottom, closeTo(0.75, 1e-6));
      expect(d.centerX, closeTo(0.5, 1e-6));
    });

    test('below the soft tier, nothing', () {
      expect(stairsDetections([raw(score: kStairsSoft - 0.01)], box), isEmpty);
      expect(stairsDetections([raw(score: kStairsSoft)], box), hasLength(1));
    });

    test('a box wholly in the padding is nothing', () {
      final inPadding = RawBox(
          classIndex: 0,
          score: 0.9,
          centerX: 0.5,
          centerY: 0.05,
          width: 0.4,
          height: 0.08);
      expect(stairsDetections([inPadding], box), isEmpty);
    });
  });
}
