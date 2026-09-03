/// Distance on the surface of the earth.
library;

import 'dart:math' as math;

import '../location/location_fix.dart';

const double _earthRadiusMetres = 6371008.8;

double _rad(double degrees) => degrees * math.pi / 180.0;

/// Great-circle distance in metres.
///
/// Haversine rather than anything cleverer. At the distances this app deals in
/// - a few kilometres between a home and a clinic - the error against a proper
/// ellipsoidal calculation is well under a metre, which is an order of
/// magnitude better than the GPS accuracy feeding it.
double metresBetween(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMetres * math.asin(math.min(1.0, math.sqrt(a)));
}

double metresBetweenFixes(LocationFix a, LocationFix b) =>
    metresBetween(a.latitude, a.longitude, b.latitude, b.longitude);

/// Mean position of a set of points.
///
/// A plain arithmetic mean of latitude and longitude. It is wrong near the
/// poles and across the antimeridian; it is correct to within centimetres for
/// points a few hundred metres apart, which is the only case this is used for.
({double latitude, double longitude}) centroidOf(List<LocationFix> fixes) {
  if (fixes.isEmpty) {
    throw ArgumentError('Cannot take the centroid of no fixes.');
  }
  var lat = 0.0;
  var lng = 0.0;
  for (final f in fixes) {
    lat += f.latitude;
    lng += f.longitude;
  }
  return (latitude: lat / fixes.length, longitude: lng / fixes.length);
}
