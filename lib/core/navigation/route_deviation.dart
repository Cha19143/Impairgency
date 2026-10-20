/// One time the walker left the route they were following.
///
/// Written to `location_history/{uid}/events` when the existing off-route
/// check trips. The document's `type` is the stable name a later guardian
/// notice can query. The timestamp is `at`, the same field every other
/// event in that collection uses.
library;

import '../places/session_event.dart';

class RouteDeviation {
  const RouteDeviation({
    required this.at,
    required this.latitude,
    required this.longitude,
    required this.distanceMetres,
  });

  /// Document field `type`. Kept as a string so a reader does not need this
  /// class to recognise the event.
  static const String type = 'route_deviation';

  final DateTime at;
  final double latitude;
  final double longitude;
  final double distanceMetres;

  /// Fields other than the Firestore timestamp. The repository adds `at`.
  Map<String, Object?> documentFields({required String sessionId}) => {
        'type': type,
        'kind': SessionEventKind.routeDeviation.name,
        'sessionId': sessionId,
        'lat': latitude,
        'lng': longitude,
        'distanceMetres': distanceMetres,
        'detail': '${distanceMetres.round()} m off the route',
      };
}
