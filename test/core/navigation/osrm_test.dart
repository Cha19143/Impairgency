import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/navigation/map_services.dart';
import 'package:impairgency/core/navigation/osrm.dart';
import 'package:impairgency/core/navigation/route.dart';

import 'map_fixtures.dart';

void main() {
  test('reads the route latitude first, as the rest of the app does', () {
    // OSRM writes [lon, lat]. Read the wrong way round, Malolos is in the
    // Indian Ocean.
    final route = parseOsrmRoute(osrmClinicRoute());
    expect(route.geometry.first.latitude, closeTo(14.84, 1e-9));
    expect(route.geometry.first.longitude, closeTo(120.81, 1e-9));
    expect(route.geometry, hasLength(5));
    expect(route.steps.first.location, route.geometry.first);
  });

  test('reads each step: what, which way, onto what, how far', () {
    final route = parseOsrmRoute(osrmClinicRoute());
    expect(route.steps.map((s) => s.type), [
      ManeuverType.depart,
      ManeuverType.turn,
      ManeuverType.turn,
      ManeuverType.turn,
      ManeuverType.arrive,
    ]);
    final left = route.steps[1];
    expect(left.modifier, ManeuverModifier.left);
    expect(left.name, 'Mabini Street');
    expect(left.distanceMetres, 80);
    expect(left.bearingAfter, 0);
    expect(route.steps[2].name, isEmpty, reason: 'a footpath with no name');
    expect(route.steps.last.modifier, ManeuverModifier.right);
  });

  test('reads the totals, and how far each end is from the path', () {
    final route = parseOsrmRoute(osrmClinicRoute());
    expect(route.distanceMetres, 275);
    expect(route.duration.inSeconds, 196);
    expect(route.startSnapMetres, 3.2);
    expect(route.endSnapMetres, 4.8);
  });

  test('car manoeuvres become the few a walker needs', () {
    Map<String, Object?> withType(String type, String? modifier) {
      final json = osrmClinicRoute();
      final step = (((json['routes'] as List).first as Map)['legs'] as List)
          .first['steps'][1] as Map;
      (step['maneuver'] as Map)['type'] = type;
      if (modifier == null) {
        (step['maneuver'] as Map).remove('modifier');
      } else {
        (step['maneuver'] as Map)['modifier'] = modifier;
      }
      return json;
    }

    ManeuverType typeOf(String type, [String? modifier = 'left']) =>
        parseOsrmRoute(withType(type, modifier)).steps[1].type;

    expect(typeOf('merge'), ManeuverType.turn);
    expect(typeOf('off ramp'), ManeuverType.turn);
    expect(typeOf('roundabout turn'), ManeuverType.turn);
    expect(typeOf('new name', 'straight'), ManeuverType.newName);
    expect(typeOf('end of road'), ManeuverType.endOfRoad);
    expect(typeOf('rotary'), ManeuverType.roundabout);
    expect(typeOf('something new', 'straight'), ManeuverType.continueOn);
    expect(typeOf('something new', null), ManeuverType.continueOn);
  });

  test('no route is its own failure; anything else unreadable is not', () {
    expect(
      () => parseOsrmRoute(osrmNoRoute),
      throwsA(isA<MapServiceException>()
          .having((e) => e.failure, 'failure', MapServiceFailure.noRoute)),
    );
    for (final bad in <Object?>[
      null,
      'Ok',
      {'code': 'InvalidQuery', 'message': 'Query string malformed'},
      {'code': 'Ok', 'routes': 'none'},
      {'code': 'Ok', 'routes': [{'legs': []}]},
    ]) {
      expect(
        () => parseOsrmRoute(bad),
        throwsA(isA<MapServiceException>().having(
            (e) => e.failure, 'failure', MapServiceFailure.unavailable)),
        reason: '$bad',
      );
    }
  });
}
