/// Directions to one place, for as long as the person walks there.
///
/// Asks for a walking route from the first clear position and follows it,
/// turn by turn. When there is no route - no connection, no path on the map,
/// a service that is down - it says which, and falls back to the
/// straight-line direction that was all this app had before; a route is
/// tried again later if the reason might pass. Leaving the route asks for
/// another, within limits, so a phone with bad GPS does not ask the free
/// service every few seconds.
///
/// Pure: positions and a routing service in, sentences out.
library;

import 'dart:async';

import '../location/location_fix.dart';
import 'destination.dart';
import 'guidance.dart';
import 'map_services.dart';
import 'route.dart';
import 'route_follower.dart';
import 'route_phrases.dart';

enum JourneyMode {
  /// No clear position yet.
  waiting,

  /// Asking for a route.
  finding,

  /// Following one.
  route,

  /// No route: the straight-line direction.
  straightLine,

  arrived,
}

/// Not more often than this, a new route for someone off the old one.
const Duration kRerouteGap = Duration(seconds: 30);

/// And not more than this many times in one journey.
const int kMaxReroutes = 8;

/// After a failure that might pass, another try after this long...
const Duration kRetryGap = Duration(seconds: 60);

/// ...this many times.
const int kMaxRetries = 3;

/// With no clear position for this long, the straight line starts anyway.
const Duration kClearPositionWait = Duration(seconds: 30);

const String kUnclearPositionPhrase = 'Your position is not clear enough for '
    'a walking route yet. $kStraightLineCaveat';

class JourneyGuide {
  JourneyGuide({
    required this.destination,
    required this.say,
    this.routing,
    this.onChanged,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        _status =
            'Heading for ${destination.label}. Waiting for your position…';

  final Destination destination;

  /// Says a sentence, behind hazard warnings.
  final void Function(String sentence) say;

  /// Null means straight-line directions only.
  final RoutingService? routing;

  /// Something on screen should change.
  final void Function()? onChanged;

  final DateTime Function() _now;

  JourneyMode _mode = JourneyMode.waiting;
  JourneyMode get mode => _mode;

  String _status;
  String get status => _status;

  WalkingRoute? _route;

  /// The route being followed, if any.
  WalkingRoute? get route => _route;

  /// How far along [route] the user is, in metres, once that is known.
  double? get along => _follower?.along;

  RouteFollower? _follower;
  NavigationSession? _straight;
  LocationFix? _lastFix;
  DateTime? _firstFixAt;

  int _generation = 0;
  bool _stopped = false;
  bool _tryingAgain = false;

  int _reroutes = 0;
  DateTime? _reroutedAt;
  int _retries = 0;
  DateTime? _failedAt;
  MapServiceFailure? _failure;

  /// A new position.
  void update(LocationFix fix) {
    if (_stopped) return;
    _lastFix = fix;
    _firstFixAt ??= _now();
    switch (_mode) {
      case JourneyMode.waiting:
        if (routing == null) {
          _mode = JourneyMode.straightLine;
          _followStraightLine(fix);
        } else if (fix.accuracyMetres <= kPoorFixMetres) {
          unawaited(_findRoute(fix));
        } else if (_now().difference(_firstFixAt!) >= kClearPositionWait) {
          _mode = JourneyMode.straightLine;
          say(kUnclearPositionPhrase);
          _followStraightLine(fix);
        } else {
          _show('Heading for ${destination.label}. Waiting for a clearer '
              'position…');
        }
      case JourneyMode.finding:
        break;
      case JourneyMode.route:
        _follow(_follower!.update(fix), fix);
      case JourneyMode.straightLine:
        _followStraightLine(fix);
        if (_mayTryAgain(fix)) unawaited(_findRoute(fix, again: true));
      case JourneyMode.arrived:
        break;
    }
  }

  /// Time passing without positions.
  void tick() {
    if (_stopped || _mode != JourneyMode.route) return;
    final guidance = _follower!.tick();
    if (guidance.say != null) say(guidance.say!);
    _show(guidance.status);
  }

  void stop() {
    _stopped = true;
    _generation++;
  }

  /// Asks for a route from [from]. [again] is a quiet retry after a failure,
  /// with the straight line carrying on meanwhile; [reroute] is for someone
  /// who has left the last route.
  Future<void> _findRoute(LocationFix from,
      {bool again = false, bool reroute = false}) async {
    final routing = this.routing;
    if (routing == null) return;
    final generation = ++_generation;
    if (again) {
      _tryingAgain = true;
    } else {
      _mode = JourneyMode.finding;
      _show(reroute
          ? 'Off the route. Finding another way…'
          : 'Finding a walking route to ${destination.label}…');
    }
    if (reroute) {
      _reroutes++;
      _reroutedAt = _now();
    }

    try {
      final WalkingRoute route;
      try {
        route = await routing.walkingRoute(
          RoutePoint(from.latitude, from.longitude),
          RoutePoint(destination.latitude, destination.longitude),
        );
      } on MapServiceException {
        rethrow;
      } catch (e) {
        throw MapServiceException(MapServiceFailure.unavailable, '$e');
      } finally {
        if (again) _tryingAgain = false;
      }
      if (_stopped || generation != _generation) return;
      if (again && _mode != JourneyMode.straightLine) return;
      _route = route;
      _follower =
          RouteFollower(route: route, to: destination.label, now: _now);
      _mode = JourneyMode.route;
      _failure = null;
      final opening = reroute
          ? 'New route found.'
          : again
              ? 'Walking route found. ${routeSummaryPhrase(route, to: destination.label)}'
              : routeSummaryPhrase(route, to: destination.label);
      final latest = _lastFix ?? from;
      final guidance = _follower!.update(latest);
      say(guidance.say == null ? opening : '$opening ${guidance.say}');
      _follow(guidance, latest, alreadySaid: true);
    } on MapServiceException catch (e) {
      if (_stopped || generation != _generation) return;
      _failure = e.failure;
      _failedAt = _now();
      // A quiet retry that failed: already on the straight line, and already
      // told why.
      if (again) return;
      _mode = JourneyMode.straightLine;
      _route = null;
      _follower = null;
      say(reroute
          ? rerouteGiveUpPhrase(destination.label)
          : routeFailurePhrase(e.failure, to: destination.label));
      final latest = _lastFix;
      if (latest != null) _followStraightLine(latest);
    }
  }

  void _follow(RouteGuidance guidance, LocationFix fix,
      {bool alreadySaid = false}) {
    if (!alreadySaid && guidance.say != null) say(guidance.say!);
    _show(guidance.status);

    if (guidance.arrived) {
      final route = _route;
      if (route != null && route.endSnapMetres > kArrivedMetres) {
        // The paths stop short of the place. The last stretch is a straight
        // line, and was said to be.
        _mode = JourneyMode.straightLine;
        _straight = NavigationSession(destination: destination, now: _now);
        _failure = null;
        _retries = kMaxRetries;
      } else {
        _mode = JourneyMode.arrived;
      }
      return;
    }

    if (guidance.offRoute) {
      final last = _reroutedAt;
      if (_reroutes >= kMaxReroutes) {
        _mode = JourneyMode.straightLine;
        _retries = kMaxRetries;
        say(rerouteGiveUpPhrase(destination.label));
        _followStraightLine(fix);
        return;
      }
      if (last == null || _now().difference(last) >= kRerouteGap) {
        say(kOffRoutePhrase);
        unawaited(_findRoute(fix, reroute: true));
      }
    }
  }

  void _followStraightLine(LocationFix fix) {
    final straight =
        _straight ??= NavigationSession(destination: destination, now: _now);
    _show(straight.statusFor(fix));
    final prompt = straight.update(fix);
    if (prompt != null) say(prompt.phrase);
    if (straight.arrived) _mode = JourneyMode.arrived;
  }

  /// Whether a failure might have passed: a connection back, a busy service
  /// free again. "No route" will not pass by waiting.
  bool _mayTryAgain(LocationFix fix) {
    if (routing == null || _tryingAgain || _retries >= kMaxRetries) {
      return false;
    }
    if (fix.accuracyMetres > kPoorFixMetres) return false;
    final failure = _failure;
    final failedAt = _failedAt;
    if (failure == MapServiceFailure.noRoute) return false;
    if (failedAt != null && _now().difference(failedAt) < kRetryGap) {
      return false;
    }
    _retries++;
    return true;
  }

  void _show(String status) {
    if (status == _status) return;
    _status = status;
    onChanged?.call();
  }
}
