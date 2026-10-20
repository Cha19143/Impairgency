import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/navigation/map_services.dart';
import 'package:impairgency/core/navigation/osrm.dart';
import 'package:impairgency/core/navigation/route.dart';
import 'package:impairgency/core/navigation/route_phrases.dart';

import 'map_fixtures.dart';

RouteStep step(ManeuverType type,
        {ManeuverModifier? modifier, String name = '', int? exit}) =>
    RouteStep(
      type: type,
      modifier: modifier,
      name: name,
      exit: exit,
      location: a,
      distanceMetres: 40,
    );

void main() {
  test('a turn names the way it turns onto, when the map has a name', () {
    expect(
        maneuverWords(step(ManeuverType.turn,
            modifier: ManeuverModifier.left, name: 'Rizal Street')),
        'turn left onto Rizal Street');
    expect(
        maneuverWords(
            step(ManeuverType.turn, modifier: ManeuverModifier.slightRight)),
        'bear right');
    expect(
        maneuverWords(
            step(ManeuverType.turn, modifier: ManeuverModifier.uturn)),
        'turn around');
  });

  test('forks, dead ends and roundabouts are said as a walker meets them', () {
    expect(
        maneuverWords(step(ManeuverType.fork,
            modifier: ManeuverModifier.slightLeft, name: 'Mabini Street')),
        'at the fork, keep left onto Mabini Street');
    expect(
        maneuverWords(
            step(ManeuverType.endOfRoad, modifier: ManeuverModifier.right)),
        'at the end of the path, turn right');
    expect(maneuverWords(step(ManeuverType.roundabout, exit: 2)),
        'at the roundabout, take the second exit');
    expect(
        maneuverWords(step(ManeuverType.continueOn,
            modifier: ManeuverModifier.left)),
        'follow the path round to the left');
  });

  test('a turn is counted down in exact numbers, then said at the corner', () {
    final left = step(ManeuverType.turn,
        modifier: ManeuverModifier.left, name: 'Mabini Street');
    expect(turnCountdownPhrase(left, 50),
        'Turn left onto Mabini Street in 50 meters.');
    expect(turnCountdownPhrase(left, 20),
        'Turn left onto Mabini Street in 20 meters.');
    expect(turnCountdownPhrase(left, 10),
        'Turn left onto Mabini Street in 10 meters.');
    expect(turnNowPhrase(left), 'Turn left onto Mabini Street now.');
    expect(turnCountdownPhrase(
            step(ManeuverType.turn, modifier: ManeuverModifier.right), 10),
        'Turn right in 10 meters.');
  });

  test('ahead, then at it', () {
    final left = step(ManeuverType.turn,
        modifier: ManeuverModifier.left, name: 'Mabini Street');
    expect(upcomingPhrase(left, 48, to: 'the clinic'),
        'In about 50 metres, turn left onto Mabini Street.');
    expect(nowPhrase(left), 'Now, turn left onto Mabini Street.');
    expect(
        upcomingPhrase(step(ManeuverType.arrive), 44, to: 'the clinic'),
        'In about 40 metres, you will reach the clinic.');
  });

  test('a second turn close behind rides along, without its name', () {
    final right = step(ManeuverType.turn, modifier: ManeuverModifier.right);
    final left = step(ManeuverType.turn,
        modifier: ManeuverModifier.left, name: 'Luna Street');
    expect(nowPhrase(right, then: left), 'Now, turn right, then turn left.');
    expect(nowPhrase(right, then: step(ManeuverType.arrive)),
        'Now, turn right.');
  });

  test('arriving says which side, or how far short the paths stop', () {
    expect(arrivalPhrase('the clinic', side: ManeuverModifier.right),
        'You have arrived at the clinic. It is on your right.');
    expect(arrivalPhrase('the clinic', endSnapMetres: 60),
        contains('about 60 metres further, in a straight line'));
  });

  test('the summary counts turns, not bends or name changes', () {
    final route = parseOsrmRoute(osrmClinicRoute());
    expect(routeSummaryPhrase(route, to: 'the clinic'),
        startsWith('Walking route to the clinic: about 300 metres, with 3 turns.'));
  });

  test('every failure says why, and that the straight line can cross roads',
      () {
    for (final failure in MapServiceFailure.values) {
      final phrase = routeFailurePhrase(failure, to: 'Home');
      expect(phrase, contains('Home'));
      expect(phrase, endsWith(kStraightLineCaveat));
    }
    expect(routeFailurePhrase(MapServiceFailure.offline, to: 'Home'),
        contains('no internet connection'));
  });

  test('the start: which way to face, when that is known', () {
    final depart = step(ManeuverType.depart, name: 'Rizal Street');
    expect(startPhrase(depart, relative: 5), 'Walk straight ahead along Rizal Street.');
    expect(startPhrase(depart, relative: -95), 'Turn left, and walk along Rizal Street.');
    expect(startPhrase(depart, relative: 175), 'Turn around, and walk along Rizal Street.');
    expect(startPhrase(depart),
        'Walk a few steps along Rizal Street, so I can tell which way you are facing.');
    expect(startPhrase(depart, startOffMetres: 35),
        startsWith('The route starts on the nearest path, about 40 metres away.'));
  });
}
