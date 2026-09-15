import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/stairs.dart';
import 'package:impairgency/core/vision/yuv_frame.dart';

const _w = 120;
const _h = 120;

List<List<int>> blank({int shade = 120}) =>
    [for (var y = 0; y < _h; y++) List.filled(_w, shade)];

/// Bright bands across the full width, every [period] rows, starting at [from].
List<List<int>> bands({
  int period = 10,
  int from = 56,
  int until = _h,
  int contrast = 90,
  double widthFraction = 1.0,
}) {
  final g = blank();
  final span = (_w * widthFraction).round();
  final start = (_w - span) ~/ 2;
  for (var y = from; y < until; y += period) {
    for (var x = start; x < start + span; x++) {
      g[y][x] = 120 + contrast;
    }
  }
  return g;
}


/// The grid the heuristic reads, for the perspective cases below.
const _size = kStairsGridSide;

/// Where each nosing of a real flight lands, from a pinhole camera model.
///
/// [bands] above describes a staircase that does not exist: one whose treads
/// are evenly spaced in the image. Perspective compresses real treads towards
/// the top of the frame, and a heuristic tuned only against [bands] can pass
/// every other test in this file and still never fire on a stairwell — which
/// is exactly what happened.
List<double> nosingRows({
  double cameraHeight = 1.4,
  double tiltDegrees = 30,
  double tread = 0.28,
  double riser = 0.18,
  double verticalFov = 62,
}) {
  final focal = (_size / 2) / tan(verticalFov / 2 * pi / 180);
  final tilt = tiltDegrees * pi / 180;
  final rows = <double>[];
  for (var n = 1; n <= 40; n++) {
    final angle = atan((cameraHeight + n * riser) / (n * tread)) - tilt;
    final row = _size / 2 + focal * tan(angle);
    if (row >= 0 && row < _size - 1) rows.add(row);
  }
  return rows;
}

/// Draws those nosings as bright lines on a plain floor.
List<List<int>> flight(
  List<double> rows, {
  int contrast = 90,
  double widthFraction = 1.0,
}) {
  final g = [for (var y = 0; y < _size; y++) List.filled(_size, 120)];
  final span = (_size * widthFraction).round();
  final start = (_size - span) ~/ 2;
  for (final r in rows) {
    final y = r.round();
    if (y < 0 || y >= _size) continue;
    for (var x = start; x < start + span; x++) {
      g[y][x] = (120 + contrast).clamp(0, 255);
    }
  }
  return g;
}

void main() {
  group('what a staircase looks like to one camera', () {
    test('evenly spaced bands low in the frame read as stairs', () {
      final reading = stairsFrom(bands());
      expect(reading.isStairs, isTrue,
          reason: 'confidence was ${reading.confidence}');
      expect(reading.treads, greaterThanOrEqualTo(kMinTreads));
      expect(reading.spacingRegularity, greaterThan(0.85));
    });

    test('more treads is not less certain', () {
      final six = stairsFrom(bands(period: 10));
      final twelve = stairsFrom(bands(period: 5));
      expect(twelve.confidence, greaterThanOrEqualTo(six.confidence));
    });
  });

  group('the things that are not stairs', () {
    test('a blank floor says nothing', () {
      final reading = stairsFrom(blank());
      expect(reading.isStairs, isFalse);
      expect(reading.confidence, 0);
      expect(reading.treads, 0);
    });

    test('vertical stripes are railings and blinds, not treads', () {
      // The false positive that matters. Consecutive rows are identical, so
      // the row-to-row profile is flat and nothing is found.
      final g = blank();
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x += 8) {
          g[y][x] = 220;
          if (x + 1 < _w) g[y][x + 1] = 220;
        }
      }
      final reading = stairsFrom(g);
      expect(reading.isStairs, isFalse,
          reason: 'confidence was ${reading.confidence}');
    });

    test('one strong edge is a threshold strip, not a flight', () {
      final reading = stairsFrom(bands(from: 80, until: 81));
      expect(reading.isStairs, isFalse);
      expect(reading.treads, lessThan(kMinTreads));
    });

    test('three edges are furniture, not a flight', () {
      final reading = stairsFrom(bands(period: 12, from: 60, until: 96));
      expect(reading.treads, lessThan(kMinTreads));
      expect(reading.isStairs, isFalse);
    });

    test('irregularly spaced edges are clutter', () {
      final g = blank();
      for (final y in [56, 59, 74, 78, 101, 116]) {
        for (var x = 0; x < _w; x++) {
          g[y][x] = 210;
        }
      }
      final reading = stairsFrom(g);
      expect(reading.spacingRegularity, lessThan(0.6));
      expect(reading.isStairs, isFalse,
          reason: 'confidence was ${reading.confidence}');
    });

    test('banding above the horizon is blinds, and is not looked at', () {
      // Venetian blinds and bookshelves band beautifully. They are not
      // underfoot, which is the entire reason the search is restricted.
      final reading = stairsFrom(bands(from: 4, until: 48));
      expect(reading.isStairs, isFalse);
    });

    test('edges that cross only a sliver of the width are not treads', () {
      // A stair nosing runs the width of the staircase. A chair leg does not.
      final reading = stairsFrom(bands(widthFraction: 0.12));
      expect(reading.isStairs, isFalse,
          reason: 'confidence was ${reading.confidence}');
    });

    test('random texture is not a staircase', () {
      final random = Random(9);
      final g = [
        for (var y = 0; y < _h; y++)
          [for (var x = 0; x < _w; x++) 90 + random.nextInt(70)]
      ];
      final reading = stairsFrom(g);
      expect(reading.isStairs, isFalse,
          reason: 'confidence was ${reading.confidence}');
    });
  });

  group('refusing to answer', () {
    test('a frame too small to judge is not a guess', () {
      expect(stairsFrom(const []).isStairs, isFalse);
      expect(
        stairsFrom([for (var y = 0; y < 8; y++) List.filled(8, 10)]).isStairs,
        isFalse,
      );
    });

    test('the threshold is a floor on speaking, not a tie-break', () {
      expect(kStairsMinConfidence, greaterThan(0.5));
      expect(StairsReading.none.isStairs, isFalse);
    });
  });

  group('a staircase as a camera actually sees one', () {
    // Every case here failed before the regularity measure was changed to look
    // at the ratio between successive gaps rather than their absolute size.
    // The best of them scored 0.383 against a threshold of 0.6.
    test('perspective-compressed treads are detected', () {
      final reading = stairsFrom(flight(nosingRows()));
      expect(reading.isStairs, isTrue,
          reason: 'confidence was ${reading.confidence}');
    });

    test('still detected when the nosings are wood, not paint', () {
      final reading = stairsFrom(flight(nosingRows(), contrast: 25));
      expect(reading.isStairs, isTrue,
          reason: 'confidence was ${reading.confidence}');
    });

    test('still detected when the flight does not fill the frame', () {
      final reading = stairsFrom(flight(nosingRows(), widthFraction: 0.7));
      expect(reading.isStairs, isTrue,
          reason: 'confidence was ${reading.confidence}');
    });

    test('still detected from a steeper angle', () {
      final reading = stairsFrom(flight(nosingRows(tiltDegrees: 36)));
      expect(reading.isStairs, isTrue,
          reason: 'confidence was ${reading.confidence}');
    });

    test('the unresolvable far end of the flight is not counted', () {
      // Beyond a few steps the treads are two or three pixels apart and say
      // nothing about spacing. Counting them would drown the steps underfoot.
      final reading = stairsFrom(flight(nosingRows()));
      expect(reading.treads, lessThan(nosingRows().length),
          reason: 'the whole flight was measured, not the near part of it');
      expect(reading.treads, greaterThanOrEqualTo(kMinTreads));
    });

    test('a flight is still told apart from clutter at the same scale', () {
      // The measure must not have become permissive enough to accept anything
      // with edges in it.
      final clutter = stairsFrom(flight(const [287, 259, 258, 230, 180, 176]));
      expect(clutter.isStairs, isFalse,
          reason: 'confidence was ${clutter.confidence}');
    });
  });

  group('from the camera', () {
    // The phone is held upright; its sensor lies on its side. A 720 by 480
    // frame from a sensor turned a quarter is 480 wide and 720 tall the right
    // way up, and a stair nosing across the upright view is a column of the
    // sensor's pixels.
    YuvFrame sensorFrame(List<double> uprightRows300,
        {int sensorOrientation = 90}) {
      const width = 720, height = 480;
      final y = Uint8List(width * height)..fillRange(0, width * height, 120);
      for (final r in uprightRows300) {
        final centre = (r * 720 / _size).round();
        for (var row = centre - 1; row <= centre + 1; row++) {
          if (row < 0 || row >= width) continue;
          // Upright row [row] is sensor column [row].
          for (var sensorRow = 0; sensorRow < height; sensorRow++) {
            y[sensorRow * width + row] = 210;
          }
        }
      }
      final uv = Uint8List((width ~/ 2) * (height ~/ 2))
        ..fillRange(0, (width ~/ 2) * (height ~/ 2), 128);
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

    List<List<int>> grid() => [
          for (var y = 0; y < kStairsGridSide; y++)
            List<int>.filled(kStairsGridSide, 0)
        ];

    test('a flight in a real frame is found the right way up', () {
      final g = grid();
      fillStairsGrid(sensorFrame(nosingRows()), g);
      final reading = stairsFrom(g);
      expect(reading.isStairs, isTrue,
          reason: 'confidence was ${reading.confidence}');
    });

    test('read without turning, the same frame is railings, not stairs', () {
      final g = grid();
      fillStairsGrid(sensorFrame(nosingRows(), sensorOrientation: 0), g);
      expect(stairsFrom(g).isStairs, isFalse);
    });

    test('only the part of the frame the search reads is sampled', () {
      final g = [
        for (var y = 0; y < kStairsGridSide; y++)
          List<int>.filled(kStairsGridSide, -1)
      ];
      fillStairsGrid(sensorFrame(nosingRows()), g);
      expect(g[10][150], -1, reason: 'above the floor');
      expect(g[200][5], -1, reason: 'the edge of the frame');
      expect(g[200][150], isNot(-1));
    });
  });

  group('what banding cannot tell apart, measured', () {
    // Characterisation, not aspiration. These are the reasons stairs warnings
    // are off by default. If the heuristic learns to tell them apart, these
    // fail - and docs/VISION.md and kStairsWarnings should change with them.
    List<double> floorLines(double spacing, {double from = 1.0, int count = 20}) {
      final focal = (_size / 2) / tan(31 * pi / 180);
      final tilt = 30 * pi / 180;
      return [
        for (var n = 0; n < count; n++)
          _size / 2 + focal * tan(atan(1.4 / (from + n * spacing)) - tilt)
      ];
    }

    test('stairs warnings are off unless a build asks for them', () {
      expect(kStairsWarnings, isFalse);
    });

    test('a tiled floor: evenly receding grout lines read as a flight', () {
      final reading = stairsFrom(flight(floorLines(0.3), contrast: 60));
      expect(reading.isStairs, isTrue,
          reason: 'confidence was ${reading.confidence}');
    });

    test('a zebra crossing reads as a flight', () {
      final g = [for (var y = 0; y < _size; y++) List.filled(_size, 60)];
      final edges = floorLines(0.5, count: 24);
      for (var i = 0; i + 1 < edges.length; i += 2) {
        final top = min(edges[i], edges[i + 1]).round();
        final bottom = max(edges[i], edges[i + 1]).round();
        for (var y = max(0, top); y < min(_size, bottom); y++) {
          for (var x = 0; x < _size; x++) {
            g[y][x] = 220;
          }
        }
      }
      final reading = stairsFrom(g);
      expect(reading.isStairs, isTrue,
          reason: 'confidence was ${reading.confidence}');
    });
  });
}
