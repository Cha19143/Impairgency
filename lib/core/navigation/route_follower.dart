/// Following a walking route, one GPS reading at a time.
///
/// Fed every position; hands back what to show and, now and then, what to
/// say. The rules are about a person walking with a phone that is often ten
/// metres wrong:
///
/// * A turn is said twice at most: once ahead ("In about 50 metres, turn
///   left"), and once at it ("Now, turn left"). A second turn close behind
///   the first rides along with it, because there is no time to say it
///   separately.
/// * Left and right come from the route, not a compass. Only the start needs
///   to know which way the person is facing, and GPS only knows that once
///   they are moving.
/// * Leaving the route takes several readings over several seconds to count,
///   so one wild reading does not set off a new route.
/// * A reading vaguer than [kPoorFixMetres] is ignored altogether.
///
/// Pure: a route and a list of readings in, sentences out, no clock but the
/// one passed in.
library;

import 'dart:math' as math;

import '../location/location_fix.dart';
import '../places/geo.dart';
import 'guidance.dart';
import 'polyline.dart';
import 'route.dart';
import 'route_phrases.dart';

/// Readings less accurate than this say nothing about which side of a street
/// someone is on, so they move nothing.
const double kPoorFixMetres = 50;

/// How far ahead of a turn it is first mentioned.
const double kUpcomingMetres = 50;

/// Nearer than this, "in about N metres" is too close to be worth saying
/// before "now".
const double kUpcomingFloorMetres = 20;

/// A turn this soon after the one before rides along with it: "Now, turn
/// left, then turn right."
const double kThenMetres = 25;

/// Off the line by more than this - or one and a half times the accuracy,
/// whichever is more - is off the route.
const double kOffRouteMetres = 25;

/// And for this many readings, over at least [kOffRouteTime], before it
/// counts.
const int kOffRouteReadings = 3;
const Duration kOffRouteTime = Duration(seconds: 8);

/// Further than this from the line at the start, the person is not on the
/// route yet - inside a building, across a car park.
const double kStartOffMetres = 20;

/// No reading for this long, and the person is told.
const Duration kLostPosition = Duration(seconds: 30);

/// "You are walking away from the route" is not repeated more often than
/// this.
const Duration kWrongWayRepeat = Duration(seconds: 30);

/// Between turns, how long a stretch goes without a word - or how far,
/// [kProgressMetres], whichever is first. Nothing was said between turns,
/// and on a long street that was a minute of silence.
const Duration kNavigationRepeat = Duration(seconds: 20);
const double kProgressMetres = 30;

class RouteGuidance {
  const RouteGuidance({
    required this.status,
    this.say,
    this.offRoute = false,
    this.arrived = false,
  });

  /// What the screen shows. Always current.
  final String status;

  /// Worth saying now, or null to stay quiet.
  final String? say;

  /// The person has left the route: another one is needed.
  final bool offRoute;

  /// The end of the route has been reached, and said.
  final bool arrived;
}

class RouteFollower {
  RouteFollower({
    required this.route,
    required this.to,
    DateTime Function()? now,
  })  : line = RouteLine(route.geometry),
        _now = now ?? DateTime.now {
    var expected = 0.0;
    var previous = 0.0;
    for (final step in route.steps) {
      final projection = line.project(
        step.location.latitude,
        step.location.longitude,
        near: math.min(expected, line.lengthMetres),
        behind: 60,
        ahead: 60,
      );
      final along = projection.offMetres <= 5
          ? projection.alongMetres
          : math.min(expected, line.lengthMetres);
      previous = math.max(previous, along);
      _manoeuvreAt.add(previous);
      expected += step.distanceMetres;
    }
    _manoeuvreAt[_manoeuvreAt.length - 1] = line.lengthMetres;
  }

  final WalkingRoute route;

  /// The place, as it is said: "Home", "Jollibee".
  final String to;

  final RouteLine line;
  final DateTime Function() _now;

  /// Where along the line each step's manoeuvre is.
  final List<double> _manoeuvreAt = [];

  double? _along;
  int _next = 1;
  final Set<int> _saidUpcoming = {};

  bool _started = false;
  bool _onRoute = false;
  bool _facingKnown = false;
  bool _arrived = false;

  int _offReadings = 0;
  DateTime? _offSince;

  int _wrongWayReadings = 0;
  DateTime? _wrongWaySaidAt;

  DateTime? _lastReadingAt;
  bool _lostSaid = false;
  bool _poorSaid = false;

  /// When, and where along, something was last said.
  DateTime? _spokeAt;
  double? _spokeAlong;

  String _status = 'Starting directions…';

  bool get arrived => _arrived;

  /// Metres along the route, once known.
  double? get along => _along;

  RouteGuidance update(LocationFix fix) {
    if (_arrived) return RouteGuidance(status: _status, arrived: true);
    if (fix.accuracyMetres > kPoorFixMetres) {
      // A reading, if a vague one: the position is not lost, and saying so
      // to someone standing still under a roof was wrong. That it is too
      // vague is said once.
      _lastReadingAt = _now();
      _lostSaid = false;
      if (_poorSaid) return RouteGuidance(status: _status);
      _poorSaid = true;
      return RouteGuidance(status: _status, say: kPoorFixPhrase);
    }
    _lastReadingAt = _now();
    _lostSaid = false;

    final projection = _project(fix);
    final said = <String>[];

    if (!_started) {
      _started = true;
      _onRoute = projection.offMetres <= kStartOffMetres;
      _along = _onRoute ? projection.alongMetres : null;
      if (!_onRoute) {
        _status = 'The route starts ${describeDistance(projection.offMetres)} '
            'away.';
        return RouteGuidance(
          status: _status,
          say: startPhrase(route.steps.first,
              startOffMetres: projection.offMetres),
        );
      }
      said.add(_start(fix, projection));
    } else if (!_onRoute) {
      if (projection.offMetres > kStartOffMetres) {
        _status = 'The route starts ${describeDistance(projection.offMetres)} '
            'away.';
        return RouteGuidance(status: _status, say: _towardsStart(fix, projection));
      }
      _onRoute = true;
      _along = projection.alongMetres;
      said.add(_start(fix, projection));
    }

    // Off the route?
    final offLimit =
        math.max(kOffRouteMetres, fix.accuracyMetres * 1.5).toDouble();
    if (projection.offMetres > offLimit) {
      _offReadings++;
      _offSince ??= fix.at;
      if (_offReadings >= kOffRouteReadings &&
          fix.at.difference(_offSince!) >= kOffRouteTime) {
        _status = 'Off the route.';
        return RouteGuidance(
          status: _status,
          say: said.isEmpty ? null : said.join(' '),
          offRoute: true,
        );
      }
      return RouteGuidance(
          status: _status, say: said.isEmpty ? null : said.join(' '));
    }
    _offReadings = 0;
    _offSince = null;

    final previousAlong = _along ?? projection.alongMetres;
    _along = math.max(previousAlong - 15, projection.alongMetres);
    final along = _along!;

    final wrongWay = _wrongWay(fix, projection, previousAlong);
    if (wrongWay != null) said.add(wrongWay);

    // Anything already walked past - a shortcut, a reading that jumped - is
    // not said late.
    while (_next < route.steps.length - 1 &&
        _manoeuvreAt[_next] + kThenMetres < along) {
      _next++;
    }

    final step = route.steps[_next];
    final distance = _manoeuvreAt[_next] - along;
    final last = _next == route.steps.length - 1;

    if (last) {
      final arriveWithin =
          math.max(kArrivedMetres, fix.accuracyMetres * 0.8).toDouble();
      final end = route.geometry.last;
      final straight = metresBetween(
          fix.latitude, fix.longitude, end.latitude, end.longitude);
      if (distance <= arriveWithin || straight <= arriveWithin) {
        _arrived = true;
        _status = route.endSnapMetres > kArrivedMetres
            ? '$to is ${describeDistance(route.endSnapMetres)} further.'
            : 'You have arrived at $to.';
        said.add(arrivalPhrase(to,
            side: step.modifier, endSnapMetres: route.endSnapMetres));
        return RouteGuidance(
            status: _status, say: said.join(' '), arrived: true);
      }
    } else {
      final nowWithin =
          math.max(6.0, math.min(fix.accuracyMetres, 12.0)).toDouble();
      if (distance <= nowWithin) {
        final following = route.steps[_next + 1];
        final gap = _manoeuvreAt[_next + 1] - _manoeuvreAt[_next];
        final ridesAlong = gap <= kThenMetres;
        said.add(nowPhrase(step, then: ridesAlong ? following : null));
        _next++;
        // The one that rode along was a warning. It is still said when it
        // comes: twenty metres is long enough to lose count of which turn
        // was next.
        if (ridesAlong) _saidUpcoming.add(_next);
        final upcoming = route.steps[_next];
        _status = nextStatus(upcoming, math.max(0, _manoeuvreAt[_next] - along),
            to: to);
        _spoke(along);
        return RouteGuidance(status: _status, say: said.join(' '));
      }
    }

    if (distance <= kUpcomingMetres &&
        distance > kUpcomingFloorMetres &&
        _saidUpcoming.add(_next)) {
      said.add(upcomingPhrase(step, distance, to: to));
    }
    _status = nextStatus(step, math.max(0, distance), to: to);
    // Not within a stretch of the turn's own warning, which is about to be
    // said anyway.
    if (said.isEmpty &&
        distance > kUpcomingMetres + kProgressMetres &&
        _progressDue(along)) {
      said.add(progressPhrase(step, distance, to: to));
    }
    if (said.isNotEmpty) _spoke(along);
    return RouteGuidance(
        status: _status, say: said.isEmpty ? null : said.join(' '));
  }

  void _spoke(double along) {
    _spokeAt = _now();
    _spokeAlong = along;
  }

  /// Whether the stretch since anything was last said is long enough, in
  /// time or in metres, for "keep going".
  bool _progressDue(double along) {
    final at = _spokeAt;
    final from = _spokeAlong;
    if (at == null || from == null) {
      _spoke(along);
      return false;
    }
    return _now().difference(at) >= kNavigationRepeat ||
        along - from >= kProgressMetres;
  }

  /// Time passing with no reading: under a roof, in a tunnel, a phone in a
  /// pocket.
  RouteGuidance tick() {
    final last = _lastReadingAt;
    if (_arrived || last == null || _lostSaid) {
      return RouteGuidance(status: _status, arrived: _arrived);
    }
    if (_now().difference(last) < kLostPosition) {
      return RouteGuidance(status: _status);
    }
    _lostSaid = true;
    return RouteGuidance(
        status: 'Waiting for your position…', say: kLostPositionPhrase);
  }

  RouteProjection _project(LocationFix fix) {
    final near = _along;
    if (near == null) return line.project(fix.latitude, fix.longitude);
    final local = line.project(fix.latitude, fix.longitude, near: near);
    if (local.offMetres <= kOffRouteMetres) return local;
    // Far from where they were - GPS came back after a gap, or they cut a
    // corner onto a later stretch. The whole line decides, if it is closer.
    final anywhere = line.project(fix.latitude, fix.longitude);
    return anywhere.offMetres < local.offMetres ? anywhere : local;
  }

  /// The first sentence on the route.
  String _start(LocationFix fix, RouteProjection projection) {
    // Joined partway along - GPS was late, or the route began inside a
    // building - so the way is the one being walked now, not the first.
    var current = 0;
    while (current < route.steps.length - 1 &&
        _manoeuvreAt[current + 1] <= projection.alongMetres) {
      current++;
    }
    final here = route.steps[current];
    final step = RouteStep(
      type: ManeuverType.depart,
      location: here.location,
      distanceMetres: here.distanceMetres,
      name: here.name,
    );
    final heading = fix.usableHeading;
    _facingKnown = heading != null;
    return startPhrase(step,
        relative: heading == null
            ? null
            : relativeAngle(
                heading: heading, bearing: _bearingOf(projection.segment)));
  }

  NavigationPrompt? _startPrompt;
  DateTime? _startPromptAt;

  /// Walking to where the route begins, in a straight line, with the same
  /// do-not-nag rule as straight-line directions.
  String? _towardsStart(LocationFix fix, RouteProjection projection) {
    final heading = fix.usableHeading;
    final target = line.pointAt(projection.alongMetres);
    final bearing = bearingDegrees(
        fix.latitude, fix.longitude, target.latitude, target.longitude);
    final turn = turnFor(
      distanceMetres: projection.offMetres,
      relative: heading == null
          ? null
          : relativeAngle(heading: heading, bearing: bearing),
    );
    final path = 'The path is ${describeDistance(projection.offMetres)} away.';
    final prompt = NavigationPrompt(
      turn: turn,
      distanceMetres: projection.offMetres,
      phrase: switch (turn) {
        Turn.straight => 'Keep going straight. $path',
        Turn.slightLeft => 'Bear slightly left. $path',
        Turn.slightRight => 'Bear slightly right. $path',
        Turn.left || Turn.sharpLeft => 'Turn left. $path',
        Turn.right || Turn.sharpRight => 'Turn right. $path',
        Turn.turnAround => 'Turn around. $path',
        _ => 'Walk a few steps so I can tell which way you are facing. $path',
      },
    );
    final now = _now();
    // The first sentence already asked for a few steps.
    final last = _startPrompt ??
        NavigationPrompt(
            turn: Turn.unknown,
            distanceMetres: projection.offMetres,
            phrase: '');
    if (!shouldAnnounce(
        next: prompt, last: last, lastAt: _startPromptAt ?? now, now: now)) {
      return null;
    }
    _startPrompt = prompt;
    _startPromptAt = now;
    return prompt.phrase;
  }

  /// Said when the person, now moving, turns out to be facing the wrong way.
  String? _wrongWay(
      LocationFix fix, RouteProjection projection, double previousAlong) {
    final heading = fix.usableHeading;
    if (heading == null) {
      _wrongWayReadings = 0;
      return null;
    }
    final relative = relativeAngle(
        heading: heading, bearing: _bearingOf(projection.segment));

    if (!_facingKnown) {
      _facingKnown = true;
      if (relative.abs() <= 60) return kRightWayPhrase;
      if (relative.abs() >= 120) {
        _wrongWaySaidAt = _now();
        return kWrongWayPhrase;
      }
      return relative < 0
          ? 'Turn left, and follow the path.'
          : 'Turn right, and follow the path.';
    }

    if (relative.abs() < 135 || projection.alongMetres > previousAlong + 1) {
      _wrongWayReadings = 0;
      return null;
    }
    _wrongWayReadings++;
    if (_wrongWayReadings < 2) return null;
    final saidAt = _wrongWaySaidAt;
    if (saidAt != null && _now().difference(saidAt) < kWrongWayRepeat) {
      return null;
    }
    _wrongWaySaidAt = _now();
    return kWrongWayPhrase;
  }

  double _bearingOf(int segment) {
    final a = line.points[segment];
    final b = line.points[segment + 1];
    return bearingDegrees(a.latitude, a.longitude, b.latitude, b.longitude);
  }
}
