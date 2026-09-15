/// A walking route: the line to follow, and the turns along it.
///
/// The testers asked for directions "like Google Maps": turn left, turn right,
/// on the way to a place chosen before leaving. The route comes from
/// OpenStreetMap's walking router (see `osrm.dart`); this is the shape the rest
/// of the app sees, so nothing past the parser knows which service drew it.
///
/// Pure, so a route is built in a test by hand.
library;

class RoutePoint {
  const RoutePoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is RoutePoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'RoutePoint($latitude, $longitude)';
}

/// What happens where one step of a route meets the next.
enum ManeuverType {
  /// The first step.
  depart,

  /// The last step: the end of the route.
  arrive,

  /// A turn onto another way.
  turn,

  /// The way bends, and the route stays on it.
  continueOn,

  /// Straight on, but the way changes its name.
  newName,

  /// The way splits.
  fork,

  /// The way ends; left or right.
  endOfRoad,

  /// Into a roundabout, out at an exit.
  roundabout,

  /// Out of a roundabout.
  exitRoundabout,
}

/// Which way a manoeuvre goes.
enum ManeuverModifier {
  uturn,
  sharpRight,
  right,
  slightRight,
  straight,
  slightLeft,
  left,
  sharpLeft,
}

class RouteStep {
  const RouteStep({
    required this.type,
    required this.location,
    required this.distanceMetres,
    this.modifier,
    this.name = '',
    this.exit,
    this.bearingAfter,
  });

  final ManeuverType type;

  /// Null when the direction does not matter - a departure, mostly.
  final ManeuverModifier? modifier;

  /// The way this step walks along, or empty when the map has no name for it
  /// - most footpaths.
  final String name;

  /// Where the manoeuvre is.
  final RoutePoint location;

  /// From this manoeuvre to the next one.
  final double distanceMetres;

  /// For a roundabout, which exit.
  final int? exit;

  /// Compass direction of the way after the manoeuvre, 0 to 360.
  final double? bearingAfter;
}

class WalkingRoute {
  const WalkingRoute({
    required this.geometry,
    required this.steps,
    required this.distanceMetres,
    required this.duration,
    this.startSnapMetres = 0,
    this.endSnapMetres = 0,
  });

  /// The whole line, start to end.
  final List<RoutePoint> geometry;

  /// Departure first, arrival last.
  final List<RouteStep> steps;

  final double distanceMetres;

  /// At the router's walking pace, which is not everyone's.
  final Duration duration;

  /// How far from the person the route begins. The router starts it on the
  /// nearest path it knows, which inside a building can be some way off.
  final double startSnapMetres;

  /// How far short of the place itself the route ends, for the same reason.
  final double endSnapMetres;

  /// The turns worth saying: every step but the departure.
  Iterable<RouteStep> get manoeuvres => steps.skip(1);
}
