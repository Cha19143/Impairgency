import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/navigation/polyline.dart';
import 'package:impairgency/core/navigation/route.dart';

import 'map_fixtures.dart';

void main() {
  final line = RouteLine([a, b, c, d, e]);

  test('measures the line in metres', () {
    expect(line.lengthMetres, closeTo(275, 0.5));
    expect(line.alongAt(1), closeTo(120, 0.2));
    expect(line.alongAt(2), closeTo(200, 0.3));
  });

  test('a position beside the line: how far along, how far off', () {
    final beside = moved(a, east: 50, north: 12);
    final p = line.project(beside.latitude, beside.longitude);
    expect(p.alongMetres, closeTo(50, 0.5));
    expect(p.offMetres, closeTo(12, 0.3));
    expect(p.segment, 0);
  });

  test('past the end of a segment, the corner is nearest', () {
    final past = moved(b, east: 10);
    final p = line.project(past.latitude, past.longitude);
    expect(p.alongMetres, closeTo(120, 0.5));
    expect(p.offMetres, closeTo(10, 0.3));
  });

  test('near where the person was, a stretch that doubles back is not taken',
      () {
    // Up one side of a street and back down the other, ten metres apart.
    final out = RoutePoint(14.84, 120.81);
    final far = moved(out, east: 200);
    final back = moved(far, north: 10);
    final home = moved(back, east: -200);
    final uTurn = RouteLine([out, far, back, home]);

    // Five metres north of the outward leg, fifty metres in: nearer the
    // return leg's line (5 m) - but the walk has only just begun.
    final here = moved(out, east: 50, north: 6);
    final anywhere = uTurn.project(here.latitude, here.longitude);
    expect(anywhere.segment, 2, reason: 'without a hint, the nearer leg wins');

    final hinted = uTurn.project(here.latitude, here.longitude, near: 45);
    expect(hinted.segment, 0);
    expect(hinted.alongMetres, closeTo(50, 0.5));
  });

  test('a point along the line', () {
    final p = line.pointAt(160);
    final expected = moved(b, north: 40);
    expect(p.latitude, closeTo(expected.latitude, 1e-6));
    expect(p.longitude, closeTo(expected.longitude, 1e-6));
    expect(line.pointAt(-5), a);
    expect(line.pointAt(9999), e);
  });

  test('one point is not a line', () {
    expect(() => RouteLine([a]), throwsArgumentError);
  });
}
