import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/navigation/map_services.dart';
import 'package:impairgency/core/navigation/osrm.dart';
import 'package:impairgency/core/navigation/place_search.dart';
import 'package:impairgency/core/navigation/route.dart';
import 'package:impairgency/core/navigation/route_phrases.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/vision/detection.dart';
import 'package:impairgency/core/vision/stairs.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/data/scan_service.dart';
import 'package:impairgency/vi/screens/saved_places_screen.dart';
import 'package:impairgency/vi/screens/scan_screen.dart';
import 'package:impairgency/vi/screens/smart_assistance_screen.dart';
import 'package:impairgency/vi/widgets/place_search_panel.dart';

import '../../core/navigation/map_fixtures.dart' as map;
import '../voice_fakes.dart';

class RecordingSpeaker implements PrioritySpeaker {
  final List<(String, SpeechPriority?)> said = [];
  @override
  String? get lastSpoken => said.isEmpty ? null : said.last.$1;
  @override
  Future<void> repeat() async {}
  @override
  Future<void> speak(String text) async => said.add((text, null));
  @override
  Future<void> speakLines(List<String> lines) async =>
      said.addAll(lines.map((l) => (l, null)));
  @override
  Future<void> announce(String text, {required SpeechPriority priority}) async =>
      said.add((text, priority));
  @override
  Future<void> stop() async {}
}

/// A scan service with no camera and no model: the test drives detections.
class FakeScan extends ScanService {
  void Function(ScanFrame)? onFrame;

  /// One frame from the camera: these objects, and this floor.
  void see(List<Detection> detections,
          {StairsReading stairs = StairsReading.none}) =>
      onFrame!(ScanFrame(detections: detections, stairs: stairs));
  int starts = 0;
  @override
  Future<bool> loadModel() async => true;
  @override
  Future<bool> start(void Function(ScanFrame) onFrame) async {
    starts++;
    this.onFrame = onFrame;
    return true;
  }

  @override
  Future<void> dispose() async {}
}

const home = Destination(
    id: 'home', label: 'Home', latitude: 14.79, longitude: 120.92,
    kind: DestinationKind.home);
const clinic = Destination(id: 'p1', label: 'Clinic', latitude: 14.8, longitude: 120.93);

Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

void main() {
  group('smart assistance - where are you going?', () {
    testWidgets('one tap on a saved place sets it', (tester) async {
      Destination? chosen;
      await tester.pumpWidget(host(SmartAssistanceScreen(
        places: const [clinic, home],
        onGo: (p) => chosen = p,
        onManagePlaces: () {},
        onBack: () {},
      )));
      await tester.tap(find.text('Home'));
      expect(chosen, home);
    });

    testWidgets('a place not saved yet says so and leads to saving it',
        (tester) async {
      var manage = 0;
      await tester.pumpWidget(host(SmartAssistanceScreen(
        places: const [home],
        onGo: (_) {},
        onManagePlaces: () => manage++,
        onBack: () {},
      )));
      expect(find.text('Work is not saved yet'), findsOneWidget);
      expect(find.text('School is not saved yet'), findsOneWidget);
      await tester.tap(find.text('Work is not saved yet'));
      expect(manage, 1);
    });

    testWidgets('a place that is not saved can be searched for, and chosen',
        (tester) async {
      Destination? chosen;
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(SmartAssistanceScreen(
        speaker: speaker,
        places: const [home],
        onGo: (p) => chosen = p,
        onManagePlaces: () {},
        onBack: () {},
        search: (query) async => PlaceSearchResult(
          found: nearbyCandidates(parsePhoton(map.photonJollibee), map.a),
          from: map.a,
        ),
      )));
      await tester.enterText(find.byType(TextField), 'jollibee');
      await tester.ensureVisible(find.text('Search'));
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(speaker.said.last.$1, '2 places found for jollibee.');
      expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);

      final second = find.textContaining('MacArthur Highway');
      await tester.ensureVisible(second);
      await tester.tap(second);
      expect(chosen?.id, 'search-N3333');
      expect(chosen?.label, 'Jollibee');
    });

    testWidgets('a search that cannot run says why', (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(SmartAssistanceScreen(
        speaker: speaker,
        places: const [home],
        onGo: (_) {},
        onManagePlaces: () {},
        onBack: () {},
        search: (_) async => const PlaceSearchResult(
            problem: 'Searching for places needs an internet connection.'),
      )));
      await tester.enterText(find.byType(TextField), 'clinic');
      await tester.ensureVisible(find.text('Search'));
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(speaker.said.last.$1,
          'Searching for places needs an internet connection.');
      expect(find.text('Searching for places needs an internet connection.'),
          findsOneWidget);
    });

    testWidgets('reads the saved places out on arrival', (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(SmartAssistanceScreen(
        speaker: speaker,
        places: const [clinic, home],
        onGo: (_) {},
        onManagePlaces: () {},
        onBack: () {},
      )));
      await tester.pump();
      expect(speaker.said.map((s) => s.$1).join(' '),
          contains('2 saved places: Home, Clinic'));
    });
  });

  group('saved places', () {
    testWidgets('saving Home uses where the user is standing', (tester) async {
      final calls = <(DestinationKind, String)>[];
      await tester.pumpWidget(host(SavedPlacesScreen(
        places: const [],
        onSaveHere: (kind, label) async {
          calls.add((kind, label));
          return null;
        },
        onRename: (_, __) async {},
        onRemove: (_) async {},
        onBack: () {},
      )));
      await tester.ensureVisible(find.text('Home'));
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(calls, [(DestinationKind.home, 'Home')]);
      expect(find.textContaining('Saved where you are now as Home'), findsOneWidget);
    });

    testWidgets('somewhere else needs a name, and the refusal is spoken',
        (tester) async {
      final speaker = RecordingSpeaker();
      var saves = 0;
      await tester.pumpWidget(host(SavedPlacesScreen(
        speaker: speaker,
        places: const [],
        onSaveHere: (_, __) async {
          saves++;
          return null;
        },
        onRename: (_, __) async {},
        onRemove: (_) async {},
        onBack: () {},
      )));
      await tester.ensureVisible(find.text('Save it with that name'));
      await tester.tap(find.text('Save it with that name'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(speaker.said.last.$1, 'Give this place a name.');
    });

    testWidgets('a position that could not be had is said, not swallowed',
        (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(SavedPlacesScreen(
        speaker: speaker,
        places: const [],
        onSaveHere: (_, __) async => 'Could not get your position.',
        onRename: (_, __) async {},
        onRemove: (_) async {},
        onBack: () {},
      )));
      await tester.ensureVisible(find.text('Home'));
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(speaker.said.last.$1, 'Could not get your position.');
    });

    testWidgets('a place not yet been to can be found by name and saved',
        (tester) async {
      final saved = <Destination>[];
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(SavedPlacesScreen(
        speaker: speaker,
        places: const [],
        onSaveHere: (_, __) async => null,
        onRename: (_, __) async {},
        onRemove: (_) async {},
        onBack: () {},
        search: (_) async => PlaceSearchResult(
          found: nearbyCandidates(parsePhoton(map.photonJollibee), map.a),
          from: map.a,
        ),
        onSaveFound: (place) async {
          saved.add(place);
          return null;
        },
      )));
      final field = find.widgetWithText(TextField, 'Search for a place that is not saved');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'jollibee');
      await tester.ensureVisible(find.text('Search'));
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      final first = find.textContaining('Paseo del Congreso');
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(saved.single.id, 'search-N1111');
      expect(speaker.said.last.$1, 'Saved Jollibee.');
    });

    testWidgets('a place can be removed', (tester) async {
      final removed = <Destination>[];
      await tester.pumpWidget(host(SavedPlacesScreen(
        places: const [clinic],
        onSaveHere: (_, __) async => null,
        onRename: (_, __) async {},
        onRemove: (p) async => removed.add(p),
        onBack: () {},
      )));
      await tester.tap(find.bySemanticsLabel('Remove Clinic'));
      await tester.pumpAndSettle();
      expect(removed, [clinic]);
    });

    testWidgets('only somewhere-else can be renamed; Home is Home',
        (tester) async {
      await tester.pumpWidget(host(SavedPlacesScreen(
        places: const [home, clinic],
        onSaveHere: (_, __) async => null,
        onRename: (_, __) async {},
        onRemove: (_) async {},
        onBack: () {},
      )));
      expect(find.bySemanticsLabel('Rename Clinic'), findsOneWidget);
      expect(find.bySemanticsLabel('Rename Home'), findsNothing);
    });
  });

  group('directions on the scan screen', () {
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

      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: scan,
        destination: home,
        positions: positions.stream,
        onStopGuidance: () {},
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

    testWidgets('stopping directions clears them without a rebuild',
        (tester) async {
      // The router's go() to the route it is already on is a no-op, so the
      // screen is never rebuilt with destination null; it has to forget the
      // destination itself, or the link and the arrival line stay put.
      final speaker = RecordingSpeaker();
      final positions = StreamController<LocationFix>();
      addTearDown(positions.close);
      var stopped = 0;

      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: FakeScan(),
        destination: home,
        positions: positions.stream,
        onStopGuidance: () => stopped++,
        onBack: () {},
      )));
      await tester.pump();
      positions.add(fix(14.788, heading: 90));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Turn left.'), findsOneWidget);

      await tester.tap(find.text('Stop directions to Home'));
      await tester.pump();

      expect(stopped, 1);
      expect(find.textContaining('Stop directions'), findsNothing);
      expect(find.textContaining('Turn left.'), findsNothing);
      expect(speaker.said.last.$1, startsWith('Directions stopped'));

      // A later fix must not bring the directions back.
      positions.add(fix(14.789, heading: 90));
      await tester.pump();
      expect(find.textContaining('Turn left.'), findsNothing);
    });

    testWidgets('names an obstacle it warned about, not a clear path',
        (tester) async {
      final scan = FakeScan();
      final named = <String>[];
      await tester.pumpWidget(host(ScanScreen(
        speaker: RecordingSpeaker(),
        service: scan,
        onObstacle: named.add,
        onBack: () {},
      )));
      await tester.pump();
      scan.see([
        const Detection(label: 'car', score: 0.9, centerX: 0.5, extent: 0.7),
      ]);
      await tester.pump();
      expect(named, ['car']);

      // Far away is guidance, not an obstacle warning.
      scan.see([
        const Detection(label: 'bench', score: 0.9, centerX: 0.5, extent: 0.1),
      ]);
      await tester.pump();
      expect(named, ['car']);
    });

    testWidgets('without a destination, nothing about directions',
        (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: FakeScan(),
        onBack: () {},
      )));
      await tester.pump();
      expect(speaker.said.last.$1, isNot(contains('Heading for')));
      expect(find.textContaining('Stop directions'), findsNothing);
    });
  });

  group('walking routes on the scan screen', () {
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
      final routing = _Routing((_, __) async => parseOsrmRoute(map.osrmClinicRoute()));

      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: scan,
        destination: clinicPlace,
        positions: positions.stream,
        routing: routing,
        onStopGuidance: () {},
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
      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: FakeScan(),
        destination: clinicPlace,
        positions: positions.stream,
        routing: _Routing((_, __) async =>
            throw const MapServiceException(MapServiceFailure.offline)),
        onStopGuidance: () {},
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

      Widget screen(Destination to, Stream<LocationFix> positions) => host(ScanScreen(
            speaker: speaker,
            service: scan,
            destination: to,
            positions: positions,
            onStopGuidance: () {},
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

  group('stairs on the scan screen', () {
    const sure =
        StairsReading(confidence: 0.9, treads: 6, spacingRegularity: 0.95);
    const unsure =
        StairsReading(confidence: 0.5, treads: 4, spacingRegularity: 0.8);

    testWidgets('a confident reading is a hazard, shown, and named to the guardian',
        (tester) async {
      final speaker = RecordingSpeaker();
      final scan = FakeScan();
      final named = <String>[];
      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: scan,
        onObstacle: named.add,
        onBack: () {},
      )));
      await tester.pump();

      scan.see(const [], stairs: sure);
      await tester.pump();
      expect(speaker.said.last, (kStairsAhead, SpeechPriority.hazard));
      expect(find.text(kStairsAhead), findsOneWidget);
      expect(named, ['stairs']);

      // The next frame, still stairs: not said again straight away.
      scan.see(const [], stairs: sure);
      await tester.pump();
      expect(speaker.said.where((s) => s.$1 == kStairsAhead), hasLength(1));
    });

    testWidgets('below the threshold, nothing about stairs is said',
        (tester) async {
      final speaker = RecordingSpeaker();
      final scan = FakeScan();
      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: scan,
        onBack: () {},
      )));
      await tester.pump();

      scan.see(const [], stairs: unsure);
      await tester.pump();
      expect(speaker.said.map((s) => s.$1), isNot(contains(kStairsAhead)));
      expect(find.text(kPathClear), findsOneWidget);
    });
  });

  group('scan, by voice', () {
    // The tester: on Scan, "help" was the only thing that worked.
    late RecordingSpeaker speaker;
    late OpenWindows mic;
    late int backs;
    late int stopped;

    Future<void> open(WidgetTester tester, {Destination? to}) async {
      speaker = RecordingSpeaker();
      mic = OpenWindows();
      backs = 0;
      stopped = 0;
      // Only a journey listens for positions, and closing a stream nobody
      // listened to never finishes.
      final positions = StreamController<LocationFix>();
      if (to != null) addTearDown(positions.close);
      final voice = voiceControllerFor(mic, speaker)..handsFree = true;
      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: FakeScan(),
        destination: to,
        positions: to == null ? null : positions.stream,
        onStopGuidance: () => stopped++,
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

    testWidgets('"stop directions" stops them; obstacles still warn',
        (tester) async {
      await open(tester, to: home);
      expect(mic.open, isTrue, reason: 'listening without a tap');

      await hear(tester, 'stop directions');
      expect(stopped, 1);
      expect(said().last, startsWith('Directions stopped'));
      expect(find.textContaining('Stop directions'), findsNothing);

      await hear(tester, 'stop directions');
      expect(stopped, 1);
      expect(said().last, 'There are no directions to stop.');
    });

    testWidgets('"go back" asks first, because the warnings stop',
        (tester) async {
      await open(tester);
      await hear(tester, 'go back');
      expect(said().last, startsWith('Leave scan?'));
      expect(backs, 0);

      await hear(tester, 'yes');
      expect(backs, 1);
    });

    testWidgets('no, or no answer, stays on scan', (tester) async {
      await open(tester);
      await hear(tester, 'go back');
      await hear(tester, 'hindi');
      expect(backs, 0);
      expect(said().last, 'Staying on scan.');

      await hear(tester, 'bumalik');
      mic.say(const NotHeard(VoiceInputFailure.nothingHeard));
      await tester.pump();
      await tester.pump();
      expect(backs, 0);
      expect(said().last, 'Staying on scan.');
    });

    testWidgets('"say that again" repeats what was last said about the path',
        (tester) async {
      await open(tester);
      await hear(tester, 'repeat');
      expect(said().last, kPathClear);
    });
  });
}

class _Routing implements RoutingService {
  _Routing(this.answer);
  final Future<WalkingRoute> Function(RoutePoint from, RoutePoint to) answer;
  @override
  Future<WalkingRoute> walkingRoute(RoutePoint from, RoutePoint to) =>
      answer(from, to);
}
