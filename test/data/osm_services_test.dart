import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:impairgency/core/navigation/map_services.dart';
import 'package:impairgency/core/navigation/route.dart';
import 'package:impairgency/data/osm_http.dart';
import 'package:impairgency/data/osrm_routing_service.dart';
import 'package:impairgency/data/photon_place_search.dart';

import '../core/navigation/map_fixtures.dart' as map;

http.Response json(Object? body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late List<http.Request> requests;
  late List<Duration> waits;
  late DateTime now;

  OsmHttp osm(Future<http.Response> Function(http.Request) answer,
          {Duration timeout = const Duration(seconds: 8)}) =>
      OsmHttp(
        client: MockClient((request) {
          requests.add(request);
          return answer(request);
        }),
        now: () => now,
        wait: (delay) async {
          waits.add(delay);
          now = now.add(delay);
        },
        timeout: timeout,
      );

  setUp(() {
    requests = [];
    waits = [];
    now = DateTime(2026, 9, 15, 9);
  });

  group('asking politely', () {
    test('every request says which app is asking, and names no person', () async {
      final http = osm((_) async => json(map.photonReverseAtA));
      await http.getJson(Uri.parse('https://photon.komoot.io/reverse?lat=1&lon=2'));
      final agent = requests.single.headers['User-Agent']!;
      expect(agent, kOsmUserAgent);
      expect(agent, contains('impairgency-capstone.web.app'));
      expect(agent, isNot(contains('@')));
    });

    test('one host is asked at most about once a second', () async {
      final http = osm((_) async => json(map.photonReverseAtA));
      final one = Uri.parse('https://photon.komoot.io/reverse?lat=1&lon=2');
      final two = Uri.parse('https://photon.komoot.io/reverse?lat=3&lon=4');
      final other = Uri.parse('https://routing.openstreetmap.de/x');
      await http.getJson(one);
      await http.getJson(two);
      expect(waits, [const Duration(milliseconds: 1100)]);
      await http.getJson(other);
      expect(waits, hasLength(1), reason: 'another host has its own turn');
    });

    test('the same search within ten minutes is answered from memory', () async {
      final http = osm((_) async => json(map.photonJollibee));
      final search = Uri.parse('https://photon.komoot.io/api?q=jollibee');
      await http.getJson(search, cache: true);
      now = now.add(const Duration(minutes: 9));
      await http.getJson(search, cache: true);
      expect(requests, hasLength(1));
      now = now.add(const Duration(minutes: 2));
      await http.getJson(search, cache: true);
      expect(requests, hasLength(2));
    });
  });

  group('failures have names', () {
    Future<MapServiceFailure> failureOf(OsmHttp http) async {
      try {
        await http.getJson(Uri.parse('https://photon.komoot.io/api?q=x'));
      } on MapServiceException catch (e) {
        return e.failure;
      }
      fail('no failure');
    }

    test('slow down', () async {
      expect(await failureOf(osm((_) async => http.Response('', 429))),
          MapServiceFailure.busy);
    });

    test('a server error', () async {
      expect(await failureOf(osm((_) async => http.Response('oops', 503))),
          MapServiceFailure.unavailable);
    });

    test('no connection', () async {
      expect(
          await failureOf(osm((_) async =>
              throw http.ClientException('Failed host lookup'))),
          MapServiceFailure.offline);
    });

    test('too slow', () async {
      final never = Completer<http.Response>();
      expect(
          await failureOf(osm((_) => never.future,
              timeout: const Duration(milliseconds: 10))),
          MapServiceFailure.timeout);
    });

    test('not JSON', () async {
      expect(await failureOf(osm((_) async => http.Response('<html>', 200))),
          MapServiceFailure.unavailable);
    });
  });

  group('walking routes', () {
    test('asks longitude first, for the walking network, with the steps', () async {
      final routing = OsrmRoutingService(
          http: osm((_) async => json(map.osrmClinicRoute())));
      final route = await routing.walkingRoute(map.a, map.e);
      final uri = requests.single.url;
      expect(uri.host, 'routing.openstreetmap.de');
      expect(uri.path, startsWith('/routed-foot/route/v1/'));
      expect(uri.pathSegments.last,
          '120.810000,14.840000;${map.e.longitude.toStringAsFixed(6)},${map.e.latitude.toStringAsFixed(6)}');
      expect(uri.queryParameters, {
        'overview': 'full',
        'steps': 'true',
        'geometries': 'geojson',
      });
      expect(route.steps, hasLength(5));
    });

    test('"no route" arrives as a 400, and is read as no route', () async {
      final routing = OsrmRoutingService(
          http: osm((_) async => json(map.osrmNoRoute, 400)));
      expect(
        () => routing.walkingRoute(map.a, const RoutePoint(14.9, 121.2)),
        throwsA(isA<MapServiceException>()
            .having((e) => e.failure, 'failure', MapServiceFailure.noRoute)),
      );
    });
  });

  group('place search', () {
    test('searches near the person, ten at most, in English', () async {
      final search = PhotonPlaceSearch(
          http: osm((_) async => json(map.photonJollibee)));
      final found = await search.search(' Jollibee ', near: map.a);
      final uri = requests.single.url;
      expect(uri.host, 'photon.komoot.io');
      expect(uri.path, '/api');
      expect(uri.queryParameters, {
        'q': 'Jollibee',
        'lat': '14.8400',
        'lon': '120.8100',
        'limit': '10',
        'lang': 'en',
      });
      expect(found, hasLength(3));
    });

    test('without a position, searches anyway', () async {
      final search = PhotonPlaceSearch(
          http: osm((_) async => json(map.photonJollibee)));
      await search.search('Jollibee');
      final params = requests.single.url.queryParameters;
      expect(params.containsKey('lat'), isFalse);
      expect(params['q'], 'Jollibee');
    });

    test('what is here', () async {
      final search = PhotonPlaceSearch(
          http: osm((_) async => json(map.photonReverseAtA)));
      final here = await search.reverse(map.a);
      expect(requests.single.url.path, '/reverse');
      expect(here?.name, 'Rizal Street');
    });

    test('nothing here is nothing, not an error', () async {
      final search = PhotonPlaceSearch(http: osm((_) async =>
          json({'type': 'FeatureCollection', 'features': []})));
      expect(await search.reverse(map.a), isNull);
    });
  });
}
