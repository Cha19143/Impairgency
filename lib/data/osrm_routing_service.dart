import '../core/navigation/map_services.dart';
import '../core/navigation/osrm.dart';
import '../core/navigation/route.dart';
import 'osm_http.dart';

/// Walking routes from the FOSSGIS OSRM server, routing.openstreetmap.de.
///
/// Free, keyless, and run by volunteers for OpenStreetMap - see [OsmHttp] for
/// the terms that come with that. `routed-foot` is the walking network; the
/// `driving` in the path is OSRM's profile slot, which that server ignores.
class OsrmRoutingService implements RoutingService {
  OsrmRoutingService({
    OsmHttp? http,
    this.base = 'https://routing.openstreetmap.de/routed-foot',
  }) : _http = http ?? OsmHttp();

  final OsmHttp _http;
  final String base;

  @override
  Future<WalkingRoute> walkingRoute(RoutePoint from, RoutePoint to) async {
    // Longitude first, as OSRM wants it.
    final coordinates = '${_c(from.longitude)},${_c(from.latitude)};'
        '${_c(to.longitude)},${_c(to.latitude)}';
    final uri = Uri.parse('$base/route/v1/driving/$coordinates').replace(
      queryParameters: const {
        'overview': 'full',
        'steps': 'true',
        'geometries': 'geojson',
      },
    );
    final json = await _http.getJson(uri, errorBody: true);
    return parseOsrmRoute(json);
  }

  /// Six decimal places is about ten centimetres - more than GPS knows, and
  /// no more than the request needs.
  static String _c(double value) => value.toStringAsFixed(6);
}
