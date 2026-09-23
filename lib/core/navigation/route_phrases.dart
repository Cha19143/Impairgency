/// The sentences of a walking route: "In about 50 metres, turn left onto
/// Rizal Street."
///
/// Said to someone who cannot glance at a map to check, so every sentence is
/// complete on its own, names the way when the map has a name for it, and
/// never gives a distance more exactly than a phone knows it.
///
/// Pure, so each wording is read in a test.
library;

import 'guidance.dart';
import 'map_services.dart';
import 'route.dart';

String _capitalise(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

const List<String> _ordinals = [
  'first',
  'second',
  'third',
  'fourth',
  'fifth',
  'sixth',
  'seventh',
  'eighth',
  'ninth',
  'tenth',
];

String _ordinal(int n) =>
    n >= 1 && n <= _ordinals.length ? _ordinals[n - 1] : 'number $n';

bool _leftward(ManeuverModifier? m) =>
    m == ManeuverModifier.left ||
    m == ManeuverModifier.slightLeft ||
    m == ManeuverModifier.sharpLeft;

bool _rightward(ManeuverModifier? m) =>
    m == ManeuverModifier.right ||
    m == ManeuverModifier.slightRight ||
    m == ManeuverModifier.sharpRight;

String _onto(String name) => name.isEmpty ? '' : ' onto $name';

/// What to do at [step], lower case, without a distance: "turn left onto
/// Rizal Street".
String maneuverWords(RouteStep step) {
  final m = step.modifier;
  final onto = _onto(step.name);
  switch (step.type) {
    case ManeuverType.depart:
      return step.name.isEmpty ? 'start walking' : 'start along ${step.name}';
    case ManeuverType.arrive:
      return 'arrive';
    case ManeuverType.turn:
      final words = switch (m) {
        ManeuverModifier.left => 'turn left',
        ManeuverModifier.right => 'turn right',
        ManeuverModifier.slightLeft => 'bear left',
        ManeuverModifier.slightRight => 'bear right',
        ManeuverModifier.sharpLeft => 'turn sharply left',
        ManeuverModifier.sharpRight => 'turn sharply right',
        ManeuverModifier.uturn => 'turn around',
        ManeuverModifier.straight || null => 'go straight on',
      };
      return '$words$onto';
    case ManeuverType.continueOn:
      if (m == ManeuverModifier.uturn) return 'turn around';
      if (_leftward(m)) return 'follow the path round to the left';
      if (_rightward(m)) return 'follow the path round to the right';
      return step.name.isEmpty
          ? 'keep going straight'
          : 'keep going straight along ${step.name}';
    case ManeuverType.newName:
      return 'keep going straight$onto';
    case ManeuverType.fork:
      final side = _leftward(m)
          ? 'keep left'
          : _rightward(m)
              ? 'keep right'
              : 'go straight on';
      return 'at the fork, $side$onto';
    case ManeuverType.endOfRoad:
      final side = _leftward(m)
          ? 'turn left'
          : _rightward(m)
              ? 'turn right'
              : 'go straight on';
      return 'at the end of the path, $side$onto';
    case ManeuverType.roundabout:
      final exit = step.exit;
      return exit == null
          ? 'go round the roundabout$onto'
          : 'at the roundabout, take the ${_ordinal(exit)} exit$onto';
    case ManeuverType.exitRoundabout:
      return 'leave the roundabout$onto';
  }
}

/// Said well before a manoeuvre: "In about 50 metres, turn left onto Rizal
/// Street."
String upcomingPhrase(RouteStep step, double metres, {required String to}) =>
    step.type == ManeuverType.arrive
        ? 'In ${describeDistance(metres)}, you will reach $to.'
        : 'In ${describeDistance(metres)}, ${maneuverWords(step)}.';

/// Said at the manoeuvre, with the one straight after it when that one is
/// too close to be said separately.
String nowPhrase(RouteStep step, {RouteStep? then}) {
  final first = 'Now, ${maneuverWords(step)}';
  if (then == null || then.type == ManeuverType.arrive) return '$first.';
  // The second without its street name: two names in one breath are hard to
  // hold on to.
  final second = maneuverWords(RouteStep(
    type: then.type,
    modifier: then.modifier,
    location: then.location,
    distanceMetres: then.distanceMetres,
    exit: then.exit,
  ));
  return '$first, then $second.';
}

/// The end of the route. [side] is where the place is, if the router said.
String arrivalPhrase(String to, {ManeuverModifier? side, double endSnapMetres = 0}) {
  final where = _leftward(side)
      ? ' It is on your left.'
      : _rightward(side)
          ? ' It is on your right.'
          : '';
  if (endSnapMetres > kArrivedMetres) {
    return 'This is as close to $to as the map\'s paths go. $to is '
        '${describeDistance(endSnapMetres)} further, in a straight line.';
  }
  return 'You have arrived at $to.$where';
}

/// Said once a route has been found.
String routeSummaryPhrase(WalkingRoute route, {required String to}) {
  final turns = route.manoeuvres
      .where((s) =>
          s.type != ManeuverType.arrive &&
          s.type != ManeuverType.newName &&
          !(s.type == ManeuverType.continueOn &&
              (s.modifier == null || s.modifier == ManeuverModifier.straight)))
      .length;
  final turnWords = switch (turns) {
    0 => 'with no turns',
    1 => 'with 1 turn',
    _ => 'with $turns turns',
  };
  return 'Walking route to $to: ${describeDistance(route.distanceMetres)}, '
      '$turnWords. Directions come from OpenStreetMap, so listen for obstacles '
      'first.';
}

/// Why following the straight line is what happens now. Always said with a
/// failure: the person has to know the direction may cross a road.
const String kStraightLineCaveat = 'Until then, I will give the straight-line '
    'direction, which can cross roads and buildings. Listen for obstacles '
    'first.';

String routeFailurePhrase(MapServiceFailure failure, {required String to}) {
  final why = switch (failure) {
    MapServiceFailure.offline =>
      'I could not get a walking route to $to, because there is no internet '
          'connection.',
    MapServiceFailure.timeout =>
      'I could not get a walking route to $to, because the map service took '
          'too long to answer.',
    MapServiceFailure.busy =>
      'I could not get a walking route to $to, because the map service is '
          'busy.',
    MapServiceFailure.noRoute => 'The map has no walking route to $to.',
    MapServiceFailure.unavailable =>
      'I could not get a walking route to $to, because the map service is not '
          'working right now.',
  };
  return '$why $kStraightLineCaveat';
}

const String kOffRoutePhrase = 'You are off the route. Finding another way.';

String rerouteGiveUpPhrase(String to) =>
    'I could not find another way to $to, so I will give the straight-line '
    'direction instead. It can cross roads and buildings. Listen for '
    'obstacles first.';

const String kLostPositionPhrase = 'I have lost your position. Stay on the '
    'path, and directions will carry on when it comes back.';

const String kWrongWayPhrase =
    'You are walking away from the route. Turn around.';

const String kRightWayPhrase = 'That is the right way. Keep going.';

/// How to begin, from where the person is standing.
///
/// [relative] is the way the route leaves compared with the way they are
/// walking, when that is known: negative left, positive right.
String startPhrase(RouteStep depart, {double? relative, double startOffMetres = 0}) {
  final along = depart.name.isEmpty ? '' : ' along ${depart.name}';
  if (startOffMetres > 20) {
    return 'The route starts on the nearest path, '
        '${describeDistance(startOffMetres)} away. Walk a few steps so I can '
        'tell which way you are facing.';
  }
  if (relative == null) {
    return 'Walk a few steps$along, so I can tell which way you are facing.';
  }
  final turn = turnFor(distanceMetres: double.infinity, relative: relative);
  return switch (turn) {
    Turn.straight => 'Walk straight ahead$along.',
    Turn.slightLeft => 'Bear left, and walk$along.',
    Turn.slightRight => 'Bear right, and walk$along.',
    Turn.left || Turn.sharpLeft => 'Turn left, and walk$along.',
    Turn.right || Turn.sharpRight => 'Turn right, and walk$along.',
    _ => 'Turn around, and walk$along.',
  };
}

/// What the screen shows between sentences.
/// Said between turns, so a long stretch is not silence: "Keep going. Turn
/// left in about 120 metres."
String progressPhrase(RouteStep step, double metres, {required String to}) =>
    step.type == ManeuverType.arrive
        ? 'Keep going. $to is in ${describeDistance(metres)}.'
        : 'Keep going. ${capitalised(maneuverWords(step))} in '
            '${describeDistance(metres)}.';

/// Said once, when readings are too vague to follow a route with.
const String kPoorFixPhrase = 'Your position is not accurate enough yet. '
    'Keep walking in the open.';

String nextStatus(RouteStep step, double metres, {required String to}) =>
    step.type == ManeuverType.arrive
        ? 'Arriving at $to in ${describeDistance(metres)}.'
        : 'Next: ${maneuverWords(step)}, in ${describeDistance(metres)}.';

String capitalised(String text) => _capitalise(text);
