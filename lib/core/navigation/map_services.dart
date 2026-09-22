/// The online map services directions and place search depend on, as the rest
/// of the app sees them.
///
/// Both are free OpenStreetMap services with no key and no promise: they can
/// be slow, busy, or unreachable from a basement. Every failure has a name
/// here, so what the person hears says which one it was - "no internet
/// connection" is something they can do something about; "the map service is
/// busy" is something they can wait out.
library;

import 'place_search.dart';
import 'route.dart';

enum MapServiceFailure {
  /// No connection, or the service could not be reached.
  offline,

  /// It was reached, and took too long to answer.
  timeout,

  /// It asked us to slow down.
  busy,

  /// It answered, and there is no walking route between the two places.
  noRoute,

  /// It answered with an error, or with something that could not be read.
  unavailable,
}

class MapServiceException implements Exception {
  const MapServiceException(this.failure, [this.detail]);

  final MapServiceFailure failure;

  /// For the log, never for the person.
  final String? detail;

  @override
  String toString() => 'MapServiceException(${failure.name}'
      '${detail == null ? '' : ': $detail'})';
}

/// A walking route between two points.
abstract interface class RoutingService {
  /// Throws [MapServiceException].
  Future<WalkingRoute> walkingRoute(RoutePoint from, RoutePoint to);
}

/// Places by name, and the name of a place.
abstract interface class PlaceSearchService {
  /// Places matching [query], the nearest to [near] favoured when there is a
  /// [near]. Throws [MapServiceException].
  Future<List<PlaceCandidate>> search(String query, {RoutePoint? near});

  /// What is at [point] - a street, a building - or null if nothing is known.
  /// Throws [MapServiceException].
  Future<PlaceCandidate?> reverse(RoutePoint point);
}

/// The credit OpenStreetMap's licence asks for wherever its data is used.
const String kOsmAttribution = '© OpenStreetMap contributors';

/// Where the credit leads, and where a wrong path on the map can be reported.
const String kOsmCopyrightUrl = 'https://www.openstreetmap.org/copyright';
const String kOsmFixTheMapUrl = 'https://www.openstreetmap.org/fixthemap';
