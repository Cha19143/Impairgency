/// Answers from the map services, for tests.
///
/// Written by hand in the shape each service documents - OSRM's
/// `/route/v1` with `steps=true&geometries=geojson&overview=full`, and
/// Photon's GeoJSON - so each rule can be tested on a route simple enough to
/// check by eye. Real answers, recorded between two landmarks in Malolos, are
/// in `recorded/` and tested in `recorded_answers_test.dart`: they are what
/// proved these shapes right, and found two branches of one shop being
/// merged into one.
///
/// The route is a made-up walk in Malolos, laid on a square grid so its
/// distances can be checked by eye:
///
///     A -- 120 m east, Rizal Street --> B
///     B -- 80 m north, Mabini Street --> C
///     C -- 15 m east, a footpath --> D
///     D -- 60 m north, a footpath --> E, the clinic on the right
library;

import 'dart:math' as math;

import 'package:impairgency/core/navigation/route.dart';

const double _metresPerDegree = 6371008.8 * math.pi / 180;

/// [from], moved [north] and [east] metres.
RoutePoint moved(RoutePoint from, {double north = 0, double east = 0}) =>
    RoutePoint(
      from.latitude + north / _metresPerDegree,
      from.longitude +
          east / (_metresPerDegree * math.cos(from.latitude * math.pi / 180)),
    );

const a = RoutePoint(14.84, 120.81);
final b = moved(a, east: 120);
final c = moved(b, north: 80);
final d = moved(c, east: 15);
final e = moved(d, north: 60);

List<double> _lonLat(RoutePoint p) => [p.longitude, p.latitude];

Map<String, Object?> _step({
  required String type,
  String? modifier,
  required String name,
  required RoutePoint at,
  required RoutePoint to,
  required double distance,
  required double bearingAfter,
}) =>
    {
      'geometry': {
        'coordinates': [_lonLat(at), _lonLat(to)],
        'type': 'LineString',
      },
      'maneuver': {
        'bearing_after': bearingAfter,
        'bearing_before': 0,
        'location': _lonLat(at),
        if (modifier != null) 'modifier': modifier,
        'type': type,
      },
      'mode': 'walking',
      'driving_side': 'right',
      'name': name,
      'intersections': const [],
      'weight': distance / 1.4,
      'duration': distance / 1.4,
      'distance': distance,
    };

Map<String, Object?> osrmClinicRoute() => {
      'code': 'Ok',
      'routes': [
        {
          'geometry': {
            'coordinates': [for (final p in [a, b, c, d, e]) _lonLat(p)],
            'type': 'LineString',
          },
          'legs': [
            {
              'steps': [
                _step(
                    type: 'depart',
                    name: 'Rizal Street',
                    at: a,
                    to: b,
                    distance: 120,
                    bearingAfter: 90),
                _step(
                    type: 'turn',
                    modifier: 'left',
                    name: 'Mabini Street',
                    at: b,
                    to: c,
                    distance: 80,
                    bearingAfter: 0),
                _step(
                    type: 'turn',
                    modifier: 'right',
                    name: '',
                    at: c,
                    to: d,
                    distance: 15,
                    bearingAfter: 90),
                _step(
                    type: 'turn',
                    modifier: 'left',
                    name: '',
                    at: d,
                    to: e,
                    distance: 60,
                    bearingAfter: 0),
                _step(
                    type: 'arrive',
                    modifier: 'right',
                    name: '',
                    at: e,
                    to: e,
                    distance: 0,
                    bearingAfter: 0),
              ],
              'summary': 'Rizal Street, Mabini Street',
              'weight': 196.4,
              'duration': 196.4,
              'distance': 275,
            },
          ],
          'weight_name': 'duration',
          'weight': 196.4,
          'duration': 196.4,
          'distance': 275,
        },
      ],
      'waypoints': [
        {'hint': 'x', 'distance': 3.2, 'name': 'Rizal Street', 'location': _lonLat(a)},
        {'hint': 'y', 'distance': 4.8, 'name': '', 'location': _lonLat(e)},
      ],
    };

const Map<String, Object?> osrmNoRoute = {
  'code': 'NoRoute',
  'message': 'Impossible route between points',
};

/// "jollibee", searched from near A.
const Map<String, Object?> photonJollibee = {
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [120.8145, 14.8433]},
      'properties': {
        'osm_type': 'N',
        'osm_id': 1111,
        'osm_key': 'amenity',
        'osm_value': 'fast_food',
        'type': 'house',
        'name': 'Jollibee',
        'street': 'Paseo del Congreso',
        'city': 'Malolos',
        'county': 'Bulacan',
        'country': 'Philippines',
        'countrycode': 'PH',
      },
    },
    {
      // The same restaurant, mapped as its building as well.
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [120.8146, 14.8434]},
      'properties': {
        'osm_type': 'W',
        'osm_id': 2222,
        'osm_key': 'building',
        'osm_value': 'yes',
        'type': 'house',
        'name': 'Jollibee',
        'street': 'Paseo del Congreso',
        'city': 'Malolos',
      },
    },
    {
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [120.8010, 14.8520]},
      'properties': {
        'osm_type': 'N',
        'osm_id': 3333,
        'osm_key': 'amenity',
        'osm_value': 'fast_food',
        'name': 'Jollibee',
        'street': 'MacArthur Highway',
        'district': 'Longos',
      },
    },
    {
      // Makati, some forty kilometres south.
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [121.0437, 14.5547]},
      'properties': {
        'osm_type': 'N',
        'osm_id': 4444,
        'name': 'Jollibee',
        'street': 'EDSA',
        'city': 'Makati',
      },
    },
    {
      // Nothing to call it.
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [120.81, 14.84]},
      'properties': {'osm_type': 'N', 'osm_id': 5555, 'osm_key': 'place'},
    },
  ],
};

/// What is at A.
const Map<String, Object?> photonReverseAtA = {
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [120.8101, 14.8401]},
      'properties': {
        'osm_type': 'W',
        'osm_id': 777,
        'osm_key': 'highway',
        'osm_value': 'residential',
        'type': 'street',
        'name': 'Rizal Street',
        'district': 'Santo Niño',
        'city': 'Malolos',
        'country': 'Philippines',
      },
    },
  ],
};
