/// Where a position is along a route line, and how far off it.
///
/// A route is a few hundred points joined by straight segments. Following it
/// means answering, for every GPS reading: how far along the line is that, and
/// how far to one side of it? The first says which turn is next; the second
/// says whether the person has left the route.
///
/// Segments are a few metres to a few hundred long, so each is flattened onto
/// a plane around its own start. At that size the error is millimetres -
/// nothing next to a phone's ten metres of GPS uncertainty.
///
/// Pure, so a route drawn by hand in a test behaves as one from the router.
library;

import 'dart:math' as math;

import '../places/geo.dart';
import 'route.dart';

class RouteProjection {
  const RouteProjection({
    required this.segment,
    required this.alongMetres,
    required this.offMetres,
  });

  /// Index of the segment's first point.
  final int segment;

  /// From the start of the line to the nearest point on it.
  final double alongMetres;

  /// From the position to that nearest point.
  final double offMetres;
}

class RouteLine {
  RouteLine(List<RoutePoint> points)
      : points = List.unmodifiable(points),
        _cumulative = _cumulativeOf(points) {
    if (points.length < 2) {
      throw ArgumentError('A route line needs at least two points.');
    }
  }

  final List<RoutePoint> points;
  final List<double> _cumulative;

  double get lengthMetres => _cumulative.last;

  /// Distance along the line to point [index].
  double alongAt(int index) => _cumulative[index];

  static List<double> _cumulativeOf(List<RoutePoint> points) {
    final result = <double>[0];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      result.add(result.last +
          metresBetween(a.latitude, a.longitude, b.latitude, b.longitude));
    }
    return result;
  }

  /// The nearest point on the line to [latitude], [longitude].
  ///
  /// With [near] - where along the line the person was last - only the stretch
  /// from [behind] metres before it to [ahead] metres after is searched. A
  /// route that doubles back on itself, down one side of a street and up the
  /// other, would otherwise put someone on the wrong side the moment GPS
  /// wandered.
  RouteProjection project(
    double latitude,
    double longitude, {
    double? near,
    double behind = 40,
    double ahead = 200,
  }) {
    var first = 0;
    var last = points.length - 2;
    var from = double.negativeInfinity;
    var to = double.infinity;
    if (near != null) {
      from = near - behind;
      to = near + ahead;
      while (first < last && _cumulative[first + 1] < from) {
        first++;
      }
      var end = first;
      while (end < last && _cumulative[end + 1] < to) {
        end++;
      }
      last = end;
    }

    RouteProjection? best;
    for (var i = first; i <= last; i++) {
      final candidate = _onSegment(i, latitude, longitude, from, to);
      if (best == null || candidate.offMetres < best.offMetres) {
        best = candidate;
      }
    }
    return best!;
  }

  /// The nearest point on segment [i], kept between [from] and [to] metres
  /// along the line - a long segment is only partly inside the stretch
  /// searched.
  RouteProjection _onSegment(
      int i, double latitude, double longitude, double from, double to) {
    final a = points[i];
    final b = points[i + 1];
    // A plane around a: x east, y north, in metres.
    final metresPerDegreeLat = _metresPerDegree;
    final metresPerDegreeLng = _metresPerDegree * math.cos(_rad(a.latitude));
    final bx = (b.longitude - a.longitude) * metresPerDegreeLng;
    final by = (b.latitude - a.latitude) * metresPerDegreeLat;
    final px = (longitude - a.longitude) * metresPerDegreeLng;
    final py = (latitude - a.latitude) * metresPerDegreeLat;

    final lengthSquared = bx * bx + by * by;
    final segmentLength = _cumulative[i + 1] - _cumulative[i];
    var low = 0.0;
    var high = 1.0;
    if (segmentLength > 0) {
      low = ((from - _cumulative[i]) / segmentLength).clamp(0.0, 1.0);
      high = ((to - _cumulative[i]) / segmentLength).clamp(0.0, 1.0);
    }
    final t = lengthSquared == 0
        ? 0.0
        : ((px * bx + py * by) / lengthSquared).clamp(low, high);
    final dx = px - t * bx;
    final dy = py - t * by;
    return RouteProjection(
      segment: i,
      alongMetres: _cumulative[i] + t * segmentLength,
      offMetres: math.sqrt(dx * dx + dy * dy),
    );
  }

  /// The point [alongMetres] from the start, clamped to the line.
  RoutePoint pointAt(double alongMetres) {
    if (alongMetres <= 0) return points.first;
    if (alongMetres >= lengthMetres) return points.last;
    var i = 0;
    while (_cumulative[i + 1] < alongMetres) {
      i++;
    }
    final length = _cumulative[i + 1] - _cumulative[i];
    final t = length == 0 ? 0.0 : (alongMetres - _cumulative[i]) / length;
    final a = points[i];
    final b = points[i + 1];
    return RoutePoint(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// Where along the line [point] is - for a manoeuvre, which the router puts
  /// on the line.
  double alongOf(RoutePoint point, {double? near}) =>
      project(point.latitude, point.longitude, near: near).alongMetres;
}

/// Metres in a degree of latitude, on the sphere `geo.dart` measures with.
const double _metresPerDegree = 6371008.8 * math.pi / 180;

double _rad(double d) => d * math.pi / 180;
