/// Grouping repeated stays into somewhere the user *goes*.
///
/// This is §2.B.2, environment learning, and it deliberately involves no model
/// and no training. Somewhere you return to is somewhere that matters; the app
/// counts returns. That is explainable in one sentence, which is worth more
/// here than an accuracy figure nobody can interrogate.
library;

import 'geo.dart';
import 'stay.dart';

class Place {
  const Place({
    required this.latitude,
    required this.longitude,
    required this.visits,
    this.label,
  });

  final double latitude;
  final double longitude;

  /// Every stay that fell inside this place, oldest first.
  final List<Stay> visits;

  /// What the user called it. Null until they say. The app never guesses a
  /// name — calling somewhere "Home" because someone sleeps there is an
  /// inference about their life, not about their location.
  final String? label;

  int get visitCount => visits.length;

  Duration get totalTime =>
      visits.fold(Duration.zero, (sum, v) => sum + v.duration);

  DateTime get firstSeen => visits.first.arrived;
  DateTime get lastSeen => visits.last.departed;

  Place copyWith({String? label}) => Place(
        latitude: latitude,
        longitude: longitude,
        visits: visits,
        label: label ?? this.label,
      );
}

/// How close two stays must be to count as the same place.
///
/// Matches [kStayRadiusMetres]: if two stays could not be told apart while
/// being detected, they should not be told apart afterwards either.
const double kPlaceRadiusMetres = kStayRadiusMetres;

/// A place needs this many visits before the app treats it as somewhere the
/// user goes rather than somewhere they once went.
///
/// §1.3 asks for "frequently visited locations"; one visit is not a frequency.
const int kMinVisitsForPlace = 2;

/// Groups stays into places by centroid linkage.
///
/// Repeatedly merges the closest pair of clusters whose centroids are within
/// [radius], until nothing is close enough. Centroid rather than single linkage
/// on purpose: single linkage chains, so a row of stays along one street would
/// collapse into a single place stretching the length of it.
///
/// O(n^2) per merge pass. Fine for the volumes here — a year of one person's
/// stays is a few hundred rows, not a few million.
List<Place> clusterIntoPlaces(
  List<Stay> stays, {
  double radius = kPlaceRadiusMetres,
}) {
  if (stays.isEmpty) return const [];

  var clusters = stays.map((s) => <Stay>[s]).toList();

  while (true) {
    double? bestDistance;
    var bestA = -1;
    var bestB = -1;

    for (var a = 0; a < clusters.length; a++) {
      for (var b = a + 1; b < clusters.length; b++) {
        final ca = _centre(clusters[a]);
        final cb = _centre(clusters[b]);
        final d = metresBetween(
            ca.latitude, ca.longitude, cb.latitude, cb.longitude);
        if (d <= radius && (bestDistance == null || d < bestDistance)) {
          bestDistance = d;
          bestA = a;
          bestB = b;
        }
      }
    }

    if (bestDistance == null) break;
    clusters[bestA] = [...clusters[bestA], ...clusters[bestB]];
    clusters.removeAt(bestB);
  }

  final places = clusters.map((group) {
    final ordered = [...group]..sort((x, y) => x.arrived.compareTo(y.arrived));
    final centre = _centre(ordered);
    return Place(
      latitude: centre.latitude,
      longitude: centre.longitude,
      visits: ordered,
    );
  }).toList();

  // Most-visited first: this ordering is what §1.3's dashboard panel shows.
  places.sort((a, b) {
    final byVisits = b.visitCount.compareTo(a.visitCount);
    return byVisits != 0 ? byVisits : b.totalTime.compareTo(a.totalTime);
  });
  return places;
}

/// Places the user actually returns to.
List<Place> frequentPlaces(
  List<Place> places, {
  int minVisits = kMinVisitsForPlace,
}) =>
    places.where((p) => p.visitCount >= minVisits).toList();

({double latitude, double longitude}) _centre(List<Stay> stays) {
  var lat = 0.0;
  var lng = 0.0;
  for (final s in stays) {
    lat += s.latitude;
    lng += s.longitude;
  }
  return (latitude: lat / stays.length, longitude: lng / stays.length);
}
