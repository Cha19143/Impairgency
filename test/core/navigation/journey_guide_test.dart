import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/navigation/journey_guide.dart';
import 'package:impairgency/core/navigation/map_services.dart';
import 'package:impairgency/core/navigation/osrm.dart';
import 'package:impairgency/core/navigation/route.dart';
import 'package:impairgency/core/navigation/route_phrases.dart';

import 'map_fixtures.dart';

final start = DateTime(2026, 9, 15, 9);

/// A router that answers when the test says.
class HeldRouting implements RoutingService {
  final requests = <(RoutePoint, RoutePoint)>[];
  final _answers = <Completer<WalkingRoute>>[];

  @override
  Future<WalkingRoute> walkingRoute(RoutePoint from, RoutePoint to) {
    requests.add((from, to));
    final answer = Completer<WalkingRoute>();
    _answers.add(answer);
    return answer.future;
  }

  Future<void> answer(WalkingRoute route) async {
    _answers.last.complete(route);
    await pumpEventQueue();
  }

  Future<void> fail(MapServiceFailure failure) async {
    _answers.last.completeError(MapServiceException(failure));
    await pumpEventQueue();
  }
}

final clinic = Destination(
    id: 'p1', label: 'the clinic', latitude: e.latitude, longitude: e.longitude);

void main() {
  late DateTime now;
  late List<String> said;
  late HeldRouting routing;
  late JourneyGuide guide;

  LocationFix at(RoutePoint p,
          {double? heading, double accuracy = 8, int seconds = 0}) =>
      LocationFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMetres: accuracy,
        at: start.add(Duration(seconds: seconds)),
        headingDegrees: heading,
        speedMetresPerSecond: heading == null ? 0 : 1.2,
      );

  void advance(int seconds) => now = start.add(Duration(seconds: seconds));

  setUp(() {
    now = start;
    said = [];
    routing = HeldRouting();
    guide = JourneyGuide(
      destination: clinic,
      say: said.add,
      routing: routing,
      now: () => now,
    );
  });

  test('routes from the first clear position, then leads the way', () async {
    guide.update(at(moved(a, north: 2), accuracy: 70));
    expect(routing.requests, isEmpty, reason: 'too vague to route from');

    guide.update(at(a, heading: 90));
    expect(routing.requests, hasLength(1));
    expect(routing.requests.single.$1.latitude, closeTo(a.latitude, 1e-9));
    expect(routing.requests.single.$2.latitude, closeTo(e.latitude, 1e-9));
    expect(guide.mode, JourneyMode.finding);
    expect(guide.status, contains('Finding a walking route'));

    await routing.answer(parseOsrmRoute(osrmClinicRoute()));
    expect(guide.mode, JourneyMode.route);
    expect(said.single, startsWith('Walking route to the clinic'));
    expect(said.single, endsWith('Walk straight ahead along Rizal Street.'),
        reason: 'the first instruction comes with the summary');

    advance(60);
    guide.update(at(moved(a, east: 72), heading: 90, seconds: 60));
    expect(said.last, 'In about 50 metres, turn left onto Mabini Street.');
  });

  test('no route says why, and the straight line takes over', () async {
    guide.update(at(a, heading: 90));
    await routing.fail(MapServiceFailure.offline);
    expect(said.first, routeFailurePhrase(MapServiceFailure.offline, to: 'the clinic'));
    expect(guide.mode, JourneyMode.straightLine);

    advance(5);
    guide.update(at(moved(a, east: 6), heading: 0, seconds: 5));
    expect(guide.status, contains('the clinic is about'),
        reason: 'straight-line directions, as before');
  });

  test('a failure that might pass is tried again a minute later, quietly',
      () async {
    guide.update(at(a, heading: 90));
    await routing.fail(MapServiceFailure.timeout);
    said.clear();

    advance(30);
    guide.update(at(moved(a, east: 4), heading: 90, seconds: 30));
    expect(routing.requests, hasLength(1), reason: 'not yet');

    advance(61);
    guide.update(at(moved(a, east: 8), heading: 90, seconds: 61));
    expect(routing.requests, hasLength(2));
    expect(guide.mode, JourneyMode.straightLine,
        reason: 'the straight line carries on while it asks');

    await routing.answer(parseOsrmRoute(osrmClinicRoute()));
    expect(said.last, startsWith('Walking route found. Walking route to the clinic'));
    expect(guide.mode, JourneyMode.route);
  });

  test('no walking route on the map is not asked for again', () async {
    guide.update(at(a, heading: 90));
    await routing.fail(MapServiceFailure.noRoute);
    for (final s in [70, 140, 210]) {
      advance(s);
      guide.update(at(moved(a, east: 4), heading: 90, seconds: s));
    }
    expect(routing.requests, hasLength(1));
  });

  test('off the route: another way, not more often than every half minute',
      () async {
    guide.update(at(a, heading: 90));
    await routing.answer(parseOsrmRoute(osrmClinicRoute()));
    said.clear();

    final away = moved(a, east: 40, north: 60);
    for (final s in [10, 14, 19]) {
      advance(s);
      guide.update(at(away, seconds: s));
    }
    expect(said, [kOffRoutePhrase]);
    expect(routing.requests, hasLength(2));
    expect(guide.status, contains('Finding another way'));

    // The new route starts where they are.
    await routing.answer(WalkingRoute(
      geometry: [away, moved(away, east: 100)],
      steps: [
        RouteStep(
            type: ManeuverType.depart,
            location: away,
            distanceMetres: 100,
            name: 'Luna Street'),
        RouteStep(
            type: ManeuverType.arrive,
            location: moved(away, east: 100),
            distanceMetres: 0),
      ],
      distanceMetres: 100,
      duration: const Duration(seconds: 70),
    ));
    expect(said.last, startsWith('New route found. Walk a few steps along Luna Street'));

    // Off the new one straight away: too soon to ask again.
    said.clear();
    final further = moved(away, north: 40);
    for (final s in [22, 26, 31, 35]) {
      advance(s);
      guide.update(at(further, seconds: s));
    }
    expect(routing.requests, hasLength(2));
    expect(said, isEmpty);

    advance(50);
    guide.update(at(further, seconds: 50));
    expect(routing.requests, hasLength(3));
  });

  test('a new route that cannot be found gives up to the straight line',
      () async {
    guide.update(at(a, heading: 90));
    await routing.answer(parseOsrmRoute(osrmClinicRoute()));
    final away = moved(a, east: 40, north: 60);
    for (final s in [10, 14, 19]) {
      advance(s);
      guide.update(at(away, seconds: s));
    }
    await routing.fail(MapServiceFailure.offline);
    expect(said, contains(rerouteGiveUpPhrase('the clinic')));
    expect(guide.mode, JourneyMode.straightLine);
  });

  test('without a routing service, straight-line directions as before', () {
    final plain = JourneyGuide(destination: clinic, say: said.add, now: () => now);
    plain.update(at(a, heading: 0));
    expect(plain.mode, JourneyMode.straightLine);
    expect(said.single, contains('the clinic is about'));
  });

  test('a position that stays vague gets the straight line after half a minute',
      () {
    guide.update(at(a, accuracy: 90));
    advance(20);
    guide.update(at(a, accuracy: 90, seconds: 20));
    expect(said, isEmpty);
    advance(31);
    guide.update(at(a, heading: 0, accuracy: 90, seconds: 31));
    expect(said.first, kUnclearPositionPhrase);
    expect(guide.mode, JourneyMode.straightLine);
  });

  test('a route that arrives after stopping is ignored', () async {
    guide.update(at(a, heading: 90));
    guide.stop();
    await routing.answer(parseOsrmRoute(osrmClinicRoute()));
    expect(said, isEmpty);
    expect(guide.route, isNull);
  });
}
