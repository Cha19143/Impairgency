import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/face_align.dart';
import 'package:impairgency/core/vision/yuv_frame.dart';

/// A grey frame, each pixel's brightness its index: easy to find again.
YuvFrame frame({int width = 8, int height = 4, int sensorOrientation = 0}) {
  final y = Uint8List.fromList(List.generate(width * height, (i) => i));
  final uv = Uint8List((width ~/ 2) * (height ~/ 2))..fillRange(0, (width ~/ 2) * (height ~/ 2), 128);
  return YuvFrame(
    width: width,
    height: height,
    y: y,
    u: uv,
    v: Uint8List.fromList(uv),
    yRowStride: width,
    uvRowStride: width ~/ 2,
    uvPixelStride: 1,
    biPlanar: false,
    sensorOrientation: sensorOrientation,
  );
}

void main() {
  test('grey stays grey', () {
    final rgb = frame().rgbAt(3, 1)!;
    expect(rgb.r, 11);
    expect(rgb.g, 11);
    expect(rgb.b, 11);
  });

  test('outside the frame is nothing', () {
    expect(frame().rgbAt(-1, 0), isNull);
    expect(frame().rgbAt(8, 0), isNull);
  });

  test('a sensor turned a quarter is read upright', () {
    // Upright, the 8 by 4 sensor is 4 wide and 8 tall. Its top-left pixel is
    // the sensor's bottom-left: row 3, column 0.
    final turned = frame(sensorOrientation: 90);
    expect(turned.uprightWidth, 4);
    expect(turned.uprightHeight, 8);
    expect(turned.rgbAt(0, 0)!.r, 3 * 8 + 0);
    expect(turned.rgbAt(3, 0)!.r, 0 * 8 + 0);
    expect(turned.rgbAt(0, 7)!.r, 3 * 8 + 7);
  });

  test('colour from interleaved planes, as iOS gives them', () {
    final y = Uint8List(16)..fillRange(0, 16, 100);
    // One colour sample per 2 by 2 block: U then V.
    final uv = Uint8List.fromList([128, 228, 128, 228, 128, 228, 128, 228]);
    final f = YuvFrame(
      width: 4, height: 4, y: y, u: uv, v: uv,
      yRowStride: 4, uvRowStride: 4, uvPixelStride: 2,
      biPlanar: true, sensorOrientation: 0,
    );
    final rgb = f.rgbAt(1, 1)!;
    expect(rgb.r, closeTo(100 + 1.402 * 100, 1e-3));
    expect(rgb.b, closeTo(100, 1e-3));
  });

  test('a square of the frame, scaled for a model, padded past the edge', () {
    final f = frame();
    final out = Float32List(2 * 2 * 3);
    fillSquare(f, const FrameSquare(6, 0, 4), out,
        side: 2, scale: 2 / 255, shift: -1, pad: 0);
    // Top-left sample: pixel (7, 1), brightness 15.
    expect(out[0], closeTo(15 * 2 / 255 - 1, 1e-6));
    // Top-right sample falls at x = 9: past the edge.
    expect(out[3], 0);
  });

  test('a head square sits on the top of the person, square', () {
    final f = frame(width: 400, height: 800);
    final head = headSquare(f, left: 0.25, top: 0.1, right: 0.75, bottom: 0.9);
    expect(head.size, closeTo(288, 1e-6), reason: '45% of 640 is taller than 200 wide');
    expect(head.left + head.size / 2, closeTo(200, 1e-6));
    expect(head.top, closeTo(80, 1e-6));
  });

  test('a face turned upright reads the frame through the inverse', () {
    final f = frame(width: 8, height: 8);
    // Crop pixel (u, v) comes from frame pixel (u + 2, v + 1).
    const toCrop = Similarity(1, 0, -2, -1);
    final out = Float32List(2 * 2 * 3);
    fillAligned(f, toCrop, out, side: 2, scale: 1, shift: 0);
    expect(out[0], 1 * 8 + 2, reason: 'crop (0, 0) is frame (2, 1)');
    expect(out[3], 1 * 8 + 3);
    expect(out[6], 2 * 8 + 2);
  });
}
