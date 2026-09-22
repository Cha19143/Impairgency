import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/depth.dart';

const int side = kDepthSide;

/// What the depth model says about a flat floor seen by a phone held up:
/// nothing much above the horizon, then nearer row by row to the bottom.
double floorAt(int row) {
  final y = row / side;
  return y < 0.35 ? 0.05 : 0.05 + (y - 0.35) / 0.65 * 0.95;
}

/// A picture of floor, with [paint] standing things on it.
Float32List scene({
  void Function(Float32List map)? paint,
  double noise = 0,
  int seed = 1,
}) {
  final random = math.Random(seed);
  final map = Float32List(side * side);
  for (var row = 0; row < side; row++) {
    for (var col = 0; col < side; col++) {
      map[row * side + col] =
          floorAt(row) + (noise == 0 ? 0 : (random.nextDouble() * 2 - 1) * noise);
    }
  }
  paint?.call(map);
  return map;
}

/// Something upright standing on the floor at [baseRow], filling columns
/// [left] to [right] from [topRow] down: all of it as near as the floor where
/// it stands.
void Function(Float32List) standing({
  required double left,
  required double right,
  required double topRow,
  required double baseRow,
}) =>
    (map) {
      final base = (baseRow * side).floor();
      final near = floorAt(base);
      for (var row = (topRow * side).floor(); row < base; row++) {
        for (var col = (left * side).floor(); col < (right * side).ceil(); col++) {
          map[row * side + col] = near;
        }
      }
    };

void main() {
  test('a floor and nothing on it is nothing', () {
    final reading = depthFrom(scene());
    expect(reading.isBlocked, isFalse);
  });

  test('a wall across the corridor, a few steps off, is ahead', () {
    final reading = depthFrom(scene(
        paint: standing(left: 0, right: 1, topRow: 0.2, baseRow: 0.8)));
    expect(reading.isBlocked, isTrue);
    expect(reading.direction, DepthDirection.ahead);
    expect(reading.isUrgent, isFalse, reason: 'a few steps off is not a stop');
  });

  test('a door right in front is a stop', () {
    final reading = depthFrom(scene(
        paint: standing(left: 0.3, right: 0.7, topRow: 0.2, baseRow: 0.93)));
    expect(reading.isBlocked, isTrue);
    expect(reading.direction, DepthDirection.ahead);
    expect(reading.isUrgent, isTrue);
  });

  test('a post on the left is on the left', () {
    final reading = depthFrom(scene(
        paint: standing(left: 0.2, right: 0.35, topRow: 0.3, baseRow: 0.85)));
    expect(reading.isBlocked, isTrue);
    expect(reading.direction, DepthDirection.left);
  });

  test('a noisy floor is still a floor', () {
    for (var seed = 1; seed <= 5; seed++) {
      expect(depthFrom(scene(noise: 0.04, seed: seed)).isBlocked, isFalse,
          reason: 'seed $seed');
    }
  });

  test('something barely above the floor is not said', () {
    // A low step, a bag: stands a little way above the line, not far enough
    // to be sure it is in the way. Silence rather than a guess.
    final reading = depthFrom(scene(paint: (map) {
      for (var row = (0.5 * side).floor(); row < (0.75 * side).floor(); row++) {
        for (var col = (0.4 * side).floor(); col < (0.6 * side).ceil(); col++) {
          map[row * side + col] += kAboveFloor * 0.6;
        }
      }
    }));
    expect(reading.isBlocked, isFalse);
  });

  test('a picture that is all one distance says nothing', () {
    final flat = Float32List(side * side)..fillRange(0, side * side, 0.4);
    expect(depthFrom(flat).isBlocked, isFalse);
  });

  test('a picture too small to read says nothing', () {
    expect(depthFrom(Float32List(10), side: 3).isBlocked, isFalse);
  });

  test('nothing at all is the default', () {
    expect(DepthReading.none.isBlocked, isFalse);
    expect(DepthReading.none.isUrgent, isFalse);
  });
}
