import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/navigation/map_services.dart';
import 'package:impairgency/core/navigation/osrm.dart';
import 'package:impairgency/core/navigation/route.dart';
import 'package:impairgency/core/navigation/route_phrases.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/vision/detection.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/vi/screens/journey_screen.dart';

import '../../core/navigation/map_fixtures.dart' as map;
import '../voice_fakes.dart';
import 'scan_fakes.dart';

/// The map, as words: no tiles are fetched in a test.
Widget drawMap(JourneyMapState state) => Text(
    'map to ${state.destination.label}, from '
    '${state.fix == null ? 'nowhere yet' : state.fix!.latitude}, '
    '${state.route?.length ?? 0} route points');

/// §2.C: Smart assistance is getting somewhere - with a map - and the
/// warnings about what is in front carry on underneath. These moved here from
/// the scan screen's tests when the directions did.
void main() {
  group('directions', () {
    LocationFix fix(double lat, {double heading = 0}) => LocationFix(
          latitude: lat,
          longitude: 120.92,
          accuracyMetres: 8,
          at: DateTime.now(),
          headingDegrees: heading,
          speedMetresPerSecond: 1.2,
        );

    testWidgets('speaks directions as navigation, behind hazards',
        (tester) async {
      final speaker = RecordingSpeaker();
      final scan = FakeScan();
      final positions = StreamController<LocationFix>();
      addTearDown(positions.close);

      await tester.pumpWidget(host(JourneyScreen(
        speaker: speaker,
        service: scan,
        mapBuilder: drawMap,
        destination: home,
        positions: positions.stream,
        onStop: () {},
        onBack: () {},
      )));
      await tester.pump();

      expect(speaker.said.last.$1, contains('Heading for Home'));

      positions.add(fix(14.788, heading: 90));
      await tester.pump();
      await tester.pump();
      final direction = speaker.said.last;
      expect(direction.$1, startsWith('Turn left.'));
      expect(direction.$2, SpeechPriority.navigation);
      expect(find.textContaining('Turn left.'), findsOneWidget);

      // A hazard from the camera outranks it.
      scan.see([
        const Detection(label: 'car', score: 0.9, centerX: 0.5, extent: 0.7),
      ]);
      await tester.pump();
      expect(speaker.said.last.$1, 'Stop. car right in front of you');
      expect(speaker.said.last.$2, SpeechPriority.hazard);

      expect(find.text('Stop directions to Home'), findsOneWidget);
    });

    testWidgets('each fix and direction goes to the journey record; '
        'arriving is said once', (tester) async {
      // The journey's summary is what the dashboard counts, and nothing
      // recorded one.
      final positions = StreamController<LocationFix>();
      addTearDown(positions.close);
      final fixes = <LocationFix>[];
      final said = <String>[];
      var arrivals = 0;

      await tester.pumpWidget(host(JourneyScreen(
        speaker: RecordingSpeaker(),
        service: FakeScan(),
        mapBuilder: drawMap,
        destination: home,
        positions: positions.stream,
        onFix: fixes.add,
        onGuidance: said.add,
        onArrived: () => arrivals++,
        onStop: () {},
        onBack: () {},
      )));
      await tester.pump();

      positions.add(fix(14.788, heading: 90));
      await tester.pump();
      expect(fixes, hasLength(1));
      expect(said, isNotEmpty);
      expect(arrivals, 0);

      positions.add(fix(14.79));
      await tester.pump();
      positions.add(fix(14.79));
      await tester.pump();
      expect(arrivals, 1);
      expect(fixes, hasLength(3));
    });

    testWidgets('lost readings are said, not only shown', (tester) async {
      // A stream that ended or errored was silent: directions just stopped.
      final speaker = RecordingSpeaker();
      final positions = StreamController<LocationFix>();
      await tester.pumpWidget(host(JourneyScreen(
        speaker: speaker,
        service: FakeScan(),
        mapBuilder: drawMap,
        destination: home,
        positions: positions.stream,
        onStop: () {},
        onBack: () {},
      )));
      await tester.pump();

      positions.addError(StateError('location off'));
      positions.addError(StateError('location off'));
      await tester.pump();
      expect(speaker.said.where((s) => s.$1 == kPositionTroublePhrase),
          hasLength(1), reason: 'once, however often it errors');

      await positions.close();
      await tester.pump();
      expect(speaker.said.last.$1, kPositionEndedPhrase);
      expect(speaker.said.last.$2, SpeechPriority.navigation);
    });

    testWidgets('stop directions hands over to the router, once',
        (tester) async {
      // Scan used to stay put and forget the destination itself, because a
      // go() to the route already open is a no-op. The journey screen leaves
      // instead, and the router clears the destination on the way out.
      final speaker = RecordingSpeaker();
      final positions = StreamController<LocationFix>();
      addTearDown(positions.close);
      var stopped = 0;

      await tester.pumpWidget(host(JourneyScreen(
        speaker: speaker,
        service: FakeScan(),
        mapBuilder: drawMap,
        destination: home,
        positions: positions.stream,
        onStop: () => stopped++,
        onBack: () {},
      )));
      await tester.pump();
      positions.add(fix(14.788, heading: 90));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Turn left.'), findsWidgets);

      await tester.tap(find.text('Stop directions to Home'));
      await tester.pump();
      expect(stopped, 1);
      expect(speaker.said.last.$1, startsWith('Directions stopped'));
      expect(speaker.said.last.$2, SpeechPriority.navigation);

      await tester.tap(find.text('Stop directions to Home'));
      await tester.pump();
      expect(stopped, 1, reason: 'handed over once');

      // A later fix does not bring the directions back.
      final before = speaker.said.length;
      positions.add(fix(14.789, heading: 90));
      await tester.pump();
      expect(speaker.said.length, before);
    });

    testWidgets('the map is drawn from where the user is', (tester) async {
      final positions = StreamController<LocationFix>();
      addTearDown(positions.close);
      await tester.pumpWidget(host(JourneyScreen(
        speaker: RecordingSpeaker(),
        service: FakeScan(),
        mapBuilder: drawMap,
        destination: home,
        positions: positions.stream,
        onStop: () {},
        onBack: () {},
      )));
      await tester.pump();
      expect(find.text('map to Home, from nowhere yet, 0 route points'),
          findsOneWidget);

      positions.add(fix(14.788, heading: 90));
      await tester.pump();
      await tester.pump();
      expect(find.text('map to Home, from 14.788, 0 route points'),
          findsOneWidget,
          reason: 'no route without routing: the straight line');
    });

    testWidgets('without a position, it says why there are no directions',
        (tester) async {
      await tester.pumpWidget(host(JourneyScreen(
        speaker: RecordingSpeaker(),
        service: FakeScan(),
        mapBuilder: drawMap,
        destination: home,
        onStop: () {},
        onBack: () {},
      )));
      await tester.pump();
      expect(find.textContaining('Directions need your location'),
          findsOneWidget);
    });
  });


  group('walking routes', () {
    final clinicPlace = Destination(
        id: 'p1',
        label: 'Clinic',
        latitude: map.e.latitude,
        longitude: map.e.longitude);

    LocationFix fixAt(RoutePoint p, {double? heading}) => LocationFix(
          latitude: p.latitude,
          longitude: p.longitude,
          accuracyMetres: 8,
          at: DateTime.now(),
          headingDegrees: heading,
          speedMetresPerSecond: heading == null ? 0 : 1.2,
        );

    testWidgets('a route is summarised, then followed, behind hazards',
        (tester) async {
      final speaker = RecordingSpeaker();
      final scan = FakeScan();
      final positions = StreamController<LocationFix>();
      addTearDown(positions.close);
      final routing = FakeRouting((_, __) async => parseOsrmRoute(map.osrmClinicRoute()));

      await tester.pumpWidget(host(JourneyScreen(
        speaker: speaker,
        service: scan,
        mapBuilder: drawMap,
        destination: clinicPlace,
        positions: positions.stream,
        routing: routing,
        onStop: () {},
        onBack: () {},
      )));
      await tester.pump();
      expect(speaker.said.last.$1, contains('Finding a walking route'));

      positions.add(fixAt(map.a, heading: 90));
      await tester.pump();
      await tester.pump();
      final summary = speaker.said.last;
      expect(summary.$1, startsWith('Walking route to Clinic'));
      expect(summary.$2, SpeechPriority.navigation);
      expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget,
          reason: 'the credit the map data asks for');
      expect(find.textContaining(RegExp(r'map to Clinic, from .*, [1-9]\d* route points')),
          findsOneWidget,
          reason: 'the map draws the route once found');

      scan.see([
        const Detection(label: 'car', score: 0.9, centerX: 0.5, extent: 0.7),
      ]);
      await tester.pump();
      expect(speaker.said.last.$2, SpeechPriority.hazard);

      positions.add(fixAt(map.moved(map.a, east: 72), heading: 90));
      await tester.pump();
      expect(speaker.said.last.$1,
          'In about 50 metres, turn left onto Mabini Street.');
      expect(find.textContaining('Next: turn left onto Mabini Street'),
          findsOneWidget);
    });

    testWidgets('no route: why, and the straight line', (tester) async {
      final speaker = RecordingSpeaker();
      final positions = StreamController<LocationFix>();
      addTearDown(positions.close);
      await tester.pumpWidget(host(JourneyScreen(
        speaker: speaker,
        service: FakeScan(),
        mapBuilder: drawMap,
        destination: clinicPlace,
        positions: positions.stream,
        routing: FakeRouting((_, __) async =>
            throw const MapServiceException(MapServiceFailure.offline)),
        onStop: () {},
        onBack: () {},
      )));
      await tester.pump();
      positions.add(fixAt(map.a, heading: 0));
      await tester.pump();
      await tester.pump();
      final said = [for (final s in speaker.said) s.$1];
      expect(said, contains(routeFailurePhrase(MapServiceFailure.offline, to: 'Clinic')));
      expect(find.textContaining('OpenStreetMap'), findsNothing);
    });

    testWidgets('a new destination changes the directions, not the camera',
        (tester) async {
      final speaker = RecordingSpeaker();
      final scan = FakeScan();
      final first = StreamController<LocationFix>();
      final second = StreamController<LocationFix>();
      addTearDown(first.close);
      addTearDown(second.close);

      Widget screen(Destination to, Stream<LocationFix> positions) => host(JourneyScreen(
            speaker: speaker,
            service: scan,
            mapBuilder: drawMap,
            destination: to,
            positions: positions,
            onStop: () {},
            onBack: () {},
          ));

      await tester.pumpWidget(screen(home, first.stream));
      await tester.pump();
      expect(find.text('Stop directions to Home'), findsOneWidget);

      await tester.pumpWidget(screen(clinic, second.stream));
      await tester.pump();
      expect(find.text('Stop directions to Clinic'), findsOneWidget);
      expect(scan.starts, 1, reason: 'obstacle warnings never stopped');

      second.add(LocationFix(
        latitude: 14.788,
        longitude: 120.92,
        accuracyMetres: 8,
        at: DateTime.now(),
        headingDegrees: 90,
        speedMetresPerSecond: 1.2,
      ));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Clinic is about'), findsOneWidget);
    });
  });


  group('the journey, by voice', () {
    late RecordingSpeaker speaker;
    late OpenWindows mic;
    late int backs;
    late int stopped;

    Future<void> open(WidgetTester tester) async {
      speaker = RecordingSpeaker();
      mic = OpenWindows();
      backs = 0;
      stopped = 0;
      final positions = StreamController<LocationFix>();
      addTearDown(positions.close);
      final voice = voiceControllerFor(mic, speaker)..handsFree = true;
      await tester.pumpWidget(host(JourneyScreen(
        speaker: speaker,
        service: FakeScan(),
        mapBuilder: drawMap,
        destination: home,
        positions: positions.stream,
        onStop: () => stopped++,
        onBack: () => backs++,
        voice: voice,
      )));
      await tester.pump();
      await tester.pump();
    }

    Future<void> hear(WidgetTester tester, String words) async {
      mic.say(Heard(words));
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    List<String> said() => [for (final s in speaker.said) s.$1];

    testWidgets('"stop directions" stops them, and hands over once',
        (tester) async {
      await open(tester);
      expect(mic.open, isTrue, reason: 'listening without a tap');

      await hear(tester, 'stop directions');
      expect(stopped, 1);
      expect(said().last, startsWith('Directions stopped'));

      await hear(tester, 'stop directions');
      expect(stopped, 1);
    });

    testWidgets('"go back" asks first, because everything stops',
        (tester) async {
      await open(tester);
      await hear(tester, 'go back');
      expect(said().last, startsWith('Leave the directions to Home?'));
      expect(backs, 0);

      await hear(tester, 'yes');
      expect(backs, 1);
    });

    testWidgets('"repeat" says the direction and what is ahead', (tester) async {
      await open(tester);
      await hear(tester, 'repeat');
      expect(said().last, contains(kNoKnownObjects));
      expect(said().last, contains('Home'));
    });
  });
}
