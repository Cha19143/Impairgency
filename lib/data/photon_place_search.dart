import '../core/navigation/map_services.dart';
import '../core/navigation/place_search.dart';
import '../core/navigation/route.dart';
import 'osm_http.dart';

/// Place search and reverse lookup from Photon, komoot's OpenStreetMap
/// geocoder at photon.komoot.io.
///
/// Free and keyless; see [OsmHttp] for the terms. A search is biased towards
/// where the person is - "Jollibee" means the one down the road - and what is
/// far away is dropped by [nearbyCandidates], not here.
class PhotonPlaceSearch implements PlaceSearchService {
  PhotonPlaceSearch({
    OsmHttp? http,
    this.base = 'https://photon.komoot.io',
  }) : _http = http ?? OsmHttp();

  final OsmHttp _http;
  final String base;

  /// Ten, not five: the nearest of five was often out of reach, and those
  /// further than [kSearchRadiusMetres] are dropped afterwards. In English,
  /// so names are said the way the voice can say them.
  @override
  Future<List<PlaceCandidate>> search(String query, {RoutePoint? near}) async {
    final uri = Uri.parse('$base/api').replace(queryParameters: {
      'q': query.trim(),
      if (near != null) ...{
        'lat': near.latitude.toStringAsFixed(4),
        'lon': near.longitude.toStringAsFixed(4),
      },
      'limit': '10',
      'lang': 'en',
    });
    return parsePhoton(await _http.getJson(uri, cache: true));
  }

  @override
  Future<PlaceCandidate?> reverse(RoutePoint point) async {
    final uri = Uri.parse('$base/reverse').replace(queryParameters: {
      'lat': point.latitude.toStringAsFixed(5),
      'lon': point.longitude.toStringAsFixed(5),
      'limit': '1',
    });
    final found = parsePhoton(await _http.getJson(uri));
    return found.isEmpty ? null : found.first;
  }
}
