import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/vision/detection.dart';
import 'package:impairgency/data/scan_service.dart';
import 'package:impairgency/vi/screens/saved_places_screen.dart';
import 'package:impairgency/vi/screens/scan_screen.dart';
import 'package:impairgency/vi/screens/smart_assistance_screen.dart';

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
  void Function(List<Detection>)? onFrame;
  @override
  Future<bool> loadModel() async => true;
  @override
  Future<bool> start(void Function(List<Detection>) onFrame) async {
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
      scan.onFrame!([
        const Detection(label: 'car', score: 0.9, centerX: 0.5, extent: 0.7),
      ]);
      await tester.pump();
      expect(speaker.said.last.$1, 'Stop. car right in front of you');
      expect(speaker.said.last.$2, SpeechPriority.hazard);

      expect(find.text('Stop directions to Home'), findsOneWidget);
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
}
