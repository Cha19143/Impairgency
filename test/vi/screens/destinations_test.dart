import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/navigation/place_search.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/vision/detection.dart';
import 'package:impairgency/core/vision/stairs.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/vi/screens/saved_places_screen.dart';
import 'package:impairgency/vi/screens/scan_screen.dart';
import 'package:impairgency/vi/screens/smart_assistance_screen.dart';
import 'package:impairgency/vi/widgets/place_search_panel.dart';

import '../../core/navigation/map_fixtures.dart' as map;
import '../voice_fakes.dart';
import 'scan_fakes.dart';


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
      // Each place read out, numbered, so nobody has to find the buttons.
      expect(speaker.said.last.$1,
          startsWith('2 places found for jollibee. First, Jollibee, Paseo del '
              'Congreso'));
      expect(speaker.said.last.$1, contains('Second, Jollibee, MacArthur Highway'));
      expect(speaker.said.last.$1, endsWith('Say the number or the name.'));
      expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);

      // The results are the screen's buttons now, first; the saved places
      // wait behind "Back to saved places".
      expect(find.text('Home'), findsNothing);
      final second = find.textContaining('MacArthur Highway');
      await tester.ensureVisible(second);
      await tester.tap(second);
      expect(chosen?.id, 'search-N3333');
      expect(chosen?.label, 'Jollibee');

      await tester.ensureVisible(find.text('Back to saved places'));
      await tester.tap(find.text('Back to saved places'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('"number two" chooses the second place found', (tester) async {
      // Two branches share a name; only the position tells them apart.
      Destination? chosen;
      final mic = OpenWindows();
      final speaker = RecordingSpeaker();
      final voice = voiceControllerFor(mic, Recording());
      await tester.pumpWidget(host(SmartAssistanceScreen(
        speaker: speaker,
        voice: voice,
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

      // Both are called Jollibee: the name alone asks for a number.
      var listening = voice.listen();
      await tester.pump();
      mic.say(const Heard('jollibee'));
      await tester.pump();
      await tester.pump();
      await listening;
      expect(chosen, isNull);
      expect(speaker.said.last.$1,
          '2 places are called Jollibee: numbers 1 and 2. Say the number.');

      listening = voice.listen();
      await tester.pump();
      mic.say(const Heard('number two'));
      await tester.pump();
      await tester.pump();
      await listening;
      expect(chosen?.id, 'search-N3333');
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

  group('the scan screen, without directions', () {
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

  group('stairs on the scan screen', () {
    // From their own model, as detections - see core/vision/stairs.dart.
    const near = Detection(
        label: kStairsLabel, score: 0.8, centerX: 0.5, extent: 0.7);
    const closeLeft = Detection(
        label: kStairsLabel, score: 0.8, centerX: 0.2, extent: 0.4);
    tearDown(() => stairsMayStop = false);

    testWidgets('named with where, told to the guardian, and kept behind '
        'narration', (tester) async {
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

      scan.see(const [closeLeft]);
      await tester.pump();
      expect(speaker.said.last,
          ('Stairs close, on your left', SpeechPriority.navigation));
      expect(named, [kStairsLabel]);
    });

    testWidgets('once the gate is passed, stairs ahead are a Stop, said once',
        (tester) async {
      stairsMayStop = true;
      final speaker = RecordingSpeaker();
      final scan = FakeScan();
      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: scan,
        onBack: () {},
      )));
      await tester.pump();

      scan.see(const [near]);
      await tester.pump();
      expect(speaker.said.last, (kStairsAhead, SpeechPriority.hazard));
      expect(find.text(kStairsAhead), findsOneWidget);

      scan.see(const [near]);
      await tester.pump();
      expect(speaker.said.where((s) => s.$1 == kStairsAhead), hasLength(1));
    });

    testWidgets('a box too unsure to mention says nothing about stairs',
        (tester) async {
      final speaker = RecordingSpeaker();
      final scan = FakeScan();
      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: scan,
        onBack: () {},
      )));
      await tester.pump();

      scan.see(const [
        Detection(label: kStairsLabel, score: 0.2, centerX: 0.5, extent: 0.7),
      ]);
      await tester.pump();
      expect(speaker.said.map((s) => s.$1.toLowerCase()),
          isNot(contains(contains('stairs'))));
    });
  });

  group('scan, by voice', () {
    // The tester: on Scan, "help" was the only thing that worked.
    late RecordingSpeaker speaker;
    late OpenWindows mic;
    late int backs;

    Future<void> open(WidgetTester tester) async {
      speaker = RecordingSpeaker();
      mic = OpenWindows();
      backs = 0;
      final voice = voiceControllerFor(mic, speaker)..handsFree = true;
      await tester.pumpWidget(host(ScanScreen(
        speaker: speaker,
        service: FakeScan(),
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

    testWidgets('"stop directions" on scan says there are none',
        (tester) async {
      // Directions live on the journey screen now.
      await open(tester);
      await hear(tester, 'stop directions');
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
      expect(said().last, kNoKnownObjects);
    });
  });
}
