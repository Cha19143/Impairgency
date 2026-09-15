/// Reading a walking route from OSRM, the router behind
/// routing.openstreetmap.de.
///
/// OSRM writes coordinates longitude first - `[lon, lat]`, GeoJSON's order -
/// and everything else in this app is latitude first. The swap happens here,
/// once, so a route that starts in the sea off Somalia instead of in Malolos
/// can only be this file's fault.
///
/// Pure: the response is a decoded JSON map, and a test feeds it one.
library;

import 'map_services.dart';
import 'route.dart';

/// The route in an OSRM `/route/v1` response, asked for with
/// `steps=true&geometries=geojson&overview=full`.
///
/// Throws [MapServiceException] with [MapServiceFailure.noRoute] when OSRM
/// says there is no way between the points, and with
/// [MapServiceFailure.unavailable] for any other error or anything that is
/// not the shape above.
WalkingRoute parseOsrmRoute(Object? json) {
  if (json is! Map) {
    throw const MapServiceException(
        MapServiceFailure.unavailable, 'not a JSON object');
  }
  final code = json['code'];
  if (code != 'Ok') {
    final noRoute = code == 'NoRoute' || code == 'NoSegment';
    throw MapServiceException(
      noRoute ? MapServiceFailure.noRoute : MapServiceFailure.unavailable,
      '$code: ${json['message']}',
    );
  }
  try {
    final routes = json['routes'] as List;
    if (routes.isEmpty) {
      throw const MapServiceException(MapServiceFailure.noRoute, 'no routes');
    }
    final route = routes.first as Map;
    final legs = route['legs'] as List;
    final steps = <RouteStep>[
      for (final leg in legs)
        for (final step in (leg as Map)['steps'] as List) _step(step as Map),
    ];
    if (steps.isEmpty) {
      throw const MapServiceException(
          MapServiceFailure.unavailable, 'a route with no steps');
    }

    final waypoints = json['waypoints'];
    double snap(int index) {
      if (waypoints is! List || waypoints.length <= index) return 0;
      final distance = (waypoints[index] as Map)['distance'];
      return distance is num ? distance.toDouble() : 0;
    }

    final geometry = _line(route['geometry']);
    return WalkingRoute(
      geometry: geometry.length >= 2
          ? geometry
          : [for (final step in steps) step.location],
      steps: steps,
      distanceMetres: (route['distance'] as num).toDouble(),
      duration: Duration(
          milliseconds: ((route['duration'] as num) * 1000).round()),
      startSnapMetres: snap(0),
      endSnapMetres: snap(waypoints is List ? waypoints.length - 1 : 0),
    );
  } on MapServiceException {
    rethrow;
  } catch (error) {
    throw MapServiceException(MapServiceFailure.unavailable, '$error');
  }
}

RouteStep _step(Map step) {
  final maneuver = step['maneuver'] as Map;
  final exit = maneuver['exit'];
  final bearing = maneuver['bearing_after'];
  return RouteStep(
    type: _type(maneuver['type'] as String?, maneuver['modifier'] as String?),
    modifier: _modifier(maneuver['modifier'] as String?),
    name: (step['name'] as String?)?.trim() ?? '',
    location: _point(maneuver['location']),
    distanceMetres: (step['distance'] as num).toDouble(),
    exit: exit is num ? exit.toInt() : null,
    bearingAfter: bearing is num ? bearing.toDouble() : null,
  );
}

/// OSRM's manoeuvre types, folded into the few a walker needs to hear about.
/// Ramps and merges are for cars; a walking route that has one is turning.
ManeuverType _type(String? type, String? modifier) => switch (type) {
      'depart' => ManeuverType.depart,
      'arrive' => ManeuverType.arrive,
      'continue' => ManeuverType.continueOn,
      'new name' || 'notification' || 'use lane' => ManeuverType.newName,
      'fork' => ManeuverType.fork,
      'end of road' => ManeuverType.endOfRoad,
      'roundabout' || 'rotary' => ManeuverType.roundabout,
      'exit roundabout' || 'exit rotary' => ManeuverType.exitRoundabout,
      // 'turn', 'merge', 'ramp', 'on ramp', 'off ramp', 'roundabout turn', and
      // whatever a later OSRM adds: a turn, if it has a direction to go in.
      _ => modifier == null || modifier == 'straight'
          ? ManeuverType.continueOn
          : ManeuverType.turn,
    };

ManeuverModifier? _modifier(String? modifier) => switch (modifier) {
      'uturn' => ManeuverModifier.uturn,
      'sharp right' => ManeuverModifier.sharpRight,
      'right' => ManeuverModifier.right,
      'slight right' => ManeuverModifier.slightRight,
      'straight' => ManeuverModifier.straight,
      'slight left' => ManeuverModifier.slightLeft,
      'left' => ManeuverModifier.left,
      'sharp left' => ManeuverModifier.sharpLeft,
      _ => null,
    };

/// `[lon, lat]`, GeoJSON's order, to a point.
RoutePoint _point(Object? pair) {
  final list = pair as List;
  return RoutePoint(
      (list[1] as num).toDouble(), (list[0] as num).toDouble());
}

List<RoutePoint> _line(Object? geometry) {
  if (geometry is! Map) return const [];
  final coordinates = geometry['coordinates'];
  if (coordinates is! List) return const [];
  return [for (final pair in coordinates) _point(pair)];
}
