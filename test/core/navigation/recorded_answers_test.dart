import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/guidance.dart';
import 'package:impairgency/core/navigation/osrm.dart';
import 'package:impairgency/core/navigation/place_search.dart';
import 'package:impairgency/core/navigation/polyline.dart';
import 'package:impairgency/core/navigation/route.dart';
import 'package:impairgency/core/navigation/route_follower.dart';
import 'package:impairgency/core/navigation/route_phrases.dart';
import 'package:impairgency/core/places/geo.dart';

/// Answers recorded from the real services on 2026-09-16, with the team's
/// agreement, between two public landmarks in Malolos: near the cathedral
/// (14.8443, 120.8111) and near Barasoain Church (14.8473, 120.8124). The
/// hand-written fixtures in `map_fixtures.dart` test the rules; these check the
/// rules were written against what the services actually send.
Object? recorded(String name) => jsonDecode(
    File('test/core/navigation/recorded/$name').readAsStringSync());

const cathedral = RoutePoint(14.8443, 120.8111);
const barasoain = RoutePoint(14.8473, 120.8124);

void main() {
  group('a real walking route, from routing.openstreetmap.de', () {
    final route = parseOsrmRoute(recorded('osrm_cathedral_to_barasoain.json'));

    test('starts and ends where it was asked - latitude first', () {
      final start = route.geometry.first;
      final end = route.geometry.last;
      expect(
          metresBetween(start.latitude, start.longitude, cathedral.latitude,
              cathedral.longitude),
          lessThan(route.startSnapMetres + 1));
      expect(
          metresBetween(
              end.latitude, end.longitude, barasoain.latitude, barasoain.longitude),
          lessThan(route.endSnapMetres + 1));
    });

    test('departs, turns onto named streets, arrives, and adds up', () {
      expect(route.steps.first.type, ManeuverType.depart);
      expect(route.steps.last.type, ManeuverType.arrive);
      expect(route.steps.map((s) => s.name),
          containsAll(['Paseo del Congreso', 'P. Burgos Street', 'Enriquez Street']));
      final steps = route.steps.fold<double>(0, (sum, s) => sum + s.distanceMetres);
      expect(steps, closeTo(route.distanceMetres, 1));
      expect(RouteLine(route.geometry).lengthMetres,
          closeTo(route.distanceMetres, route.distanceMetres * 0.05),
          reason: 'the line the follower measures agrees with the router');
    });

    test('every step can be said', () {
      for (final step in route.manoeuvres) {
        expect(maneuverWords(step), isNotEmpty);
      }
      expect(nowPhrase(route.steps[2]), 'Now, turn left onto P. Burgos Street.');
      expect(routeSummaryPhrase(route, to: 'Barasoain Church'),
          startsWith('Walking route to Barasoain Church: about 450 metres'));
    });

    test('walked from end to end, each turn is said once and arrival once', () {
      final start = DateTime(2026, 9, 16, 9);
      var now = start;
      final follower =
          RouteFollower(route: route, to: 'Barasoain Church', now: () => now);
      final line = RouteLine(route.geometry);
      final said = <String>[];
      var second = 0;
      for (var along = 0.0; along <= line.lengthMetres; along += 4) {
        final here = line.pointAt(along);
        final ahead = line.pointAt(math.min(along + 3, line.lengthMetres));
        final heading = bearingDegrees(
            here.latitude, here.longitude, ahead.latitude, ahead.longitude);
        now = start.add(Duration(seconds: second));
        final guidance = follower.update(LocationFix(
          latitude: here.latitude,
          longitude: here.longitude,
          accuracyMetres: 8,
          at: now,
          headingDegrees: heading,
          speedMetresPerSecond: 1.2,
        ));
        if (guidance.say != null) said.add(guidance.say!);
        second += 3;
      }

      expect(said.first, startsWith('Walk straight ahead.'));
      expect(said.where((s) => s.contains('Now, turn left onto P. Burgos Street')),
          hasLength(1));
      expect(said.where((s) => s.contains('Now, turn right onto Enriquez Street')),
          hasLength(1));
      expect(said.where((s) => s.startsWith('You have arrived')), hasLength(1));
      expect(said, isNot(contains(kWrongWayPhrase)));
      expect(follower.arrived, isTrue);
    });
  });

  group('a real place search, from photon.komoot.io', () {
    test('finds Jollibee near the cathedral, each told apart by street and town',
        () {
      final found = nearbyCandidates(
          parsePhoton(recorded('photon_jollibee_malolos.json')), cathedral);
      expect(found, hasLength(5));
      expect(found.every((p) => p.label == 'Jollibee'), isTrue);
      expect(describeCandidate(found.first, from: cathedral),
          'Jollibee, M. Crisostomo Street, Malolos, about 200 metres away.');
      expect(found.map((p) => p.street).toSet(), hasLength(greaterThan(1)));
    });

    test('what is at a spot is named by its street, not the shop on it', () {
      final here = parsePhoton(recorded('photon_reverse_cathedral.json')).single;
      expect(here.name, 'Ystilo Salon');
      expect(nearbyDescription(here), 'near P. Burgos Street, Malolos');
    });
  });
}
