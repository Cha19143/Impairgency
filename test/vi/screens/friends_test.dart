import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/vision/detection.dart';
import 'package:impairgency/core/vision/stairs.dart';
import 'package:impairgency/core/vision/faces.dart';
import 'package:impairgency/core/vision/friend_recognition.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/data/scan_service.dart';
import 'package:impairgency/vi/screens/scan_screen.dart';
import 'package:impairgency/vi/voice_controller.dart';

import '../../core/vision/friend_fakes.dart';
import '../voice_fakes.dart';

class Said implements PrioritySpeaker {
  final List<(String, SpeechPriority?)> said = [];
  List<String> get words => [for (final s in said) s.$1];
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

/// No camera, no models: the test hands over detections and faces.
class FaceScan extends ScanService {
  FaceScan({this.modelsLoad = true});
  final bool modelsLoad;
  void Function(ScanFrame)? onFrame;

  /// One frame from the camera: these objects, and this floor.
  void see(List<Detection> detections,
          {StairsReading stairs = StairsReading.none}) =>
      onFrame!(ScanFrame(detections: detections, stairs: stairs));
  FaceWatch? watch;

  @override
  Future<bool> loadModel() async => true;
  @override
  Future<bool> start(void Function(ScanFrame) onFrame) async {
    this.onFrame = onFrame;
    return true;
  }

  @override
  Future<bool> watchFaces(FaceWatch? watch) async {
    this.watch = watch;
    return modelsLoad;
  }

  @override
  Future<void> dispose() async {}
}

final t0 = DateTime(2026, 9, 15, 9);

final samFace = l2Normalize([1, 0.1, 0, 0]);
final sam = Friend(id: 'f1', name: 'Sam', embeddings: [l2Normalize([1, 0, 0, 0])], savedAt: t0);

FaceObservation seen(List<double> embedding, {int ms = 0}) => FaceObservation(
    embedding: embedding, width: 0.3, centerX: 0.5, rollDegrees: 0, at: t0.add(Duration(milliseconds: ms)));

Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

void main() {
  late Said speaker;
  late FaceScan scan;
  late MemoryStore store;
  late DateTime now;
  late OpenWindows mic;
  late VoiceController voice;

  FriendRecognition recognition() => FriendRecognition(
        store: store,
        owner: 'u1',
        say: (s) => speaker.announce(s, priority: SpeechPriority.info),
        now: () => now,
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester,
      {FriendRecognition? friends, bool modelsLoad = true, String? meet}) async {
    scan = FaceScan(modelsLoad: modelsLoad);
    await tester.pumpWidget(host(ScanScreen(
      speaker: speaker,
      service: scan,
      voice: voice,
      friends: friends,
      meetFriend: meet,
      onBack: () {},
    )));
    await settle(tester);
  }

  /// A tap on the microphone, and [words] said into it.
  Future<void> say(WidgetTester tester, String words) async {
    unawaited(voice.listen());
    await settle(tester);
    mic.say(Heard(words));
    await settle(tester);
  }

  setUp(() {
    speaker = Said();
    store = MemoryStore();
    now = t0;
    mic = OpenWindows();
    voice = voiceControllerFor(mic, speaker);
  });

  testWidgets('a saved friend is named, at information priority', (tester) async {
    store.saved['u1'] = [sam];
    await open(tester, friends: recognition());
    expect(scan.watch, isNotNull, reason: 'faces are looked for');

    scan.watch!.onFaces([seen(samFace)]);
    scan.watch!.onFaces([seen(samFace, ms: 500)]);
    await settle(tester);
    expect(speaker.said.last, ('Your friend Sam is in front of you.', SpeechPriority.info));
  });

  testWidgets('"hello friend Sam": Sam is asked, says yes, and is saved',
      (tester) async {
    await open(tester, friends: recognition());
    await say(tester, 'hello friend sam');
    expect(speaker.words.last, friendConsentQuestion('Sam'));

    mic.say(const Heard('yes'));
    await settle(tester);
    expect(speaker.words.last, startsWith("Point the phone at Sam's face"));
    expect(scan.watch!.enrolling, isTrue);

    // Only hazards talk over it.
    scan.see([const Detection(label: 'person', score: 0.9, centerX: 0.5, extent: 0.4)]);
    await settle(tester);
    expect(speaker.words.last, startsWith("Point the phone at Sam's face"));

    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(milliseconds: 400));
      scan.watch!.onFaces([seen(l2Normalize([0, 1, 0.02 * i, 0]))]);
      await settle(tester);
    }
    expect(speaker.words.last, 'Saved Sam. I will tell you when Sam is nearby.');
    expect(store.saved['u1']!.single.name, 'Sam');
    expect(scan.watch!.enrolling, isFalse);
  });

  testWidgets('no answer from the friend, and nothing is kept', (tester) async {
    await open(tester, friends: recognition());
    await say(tester, 'hello friend sam');
    mic.say(const NotHeard(VoiceInputFailure.nothingHeard));
    await settle(tester);
    expect(speaker.words.last, 'Nothing was saved.');
    expect(store.saves, 0);
  });

  testWidgets('said on another screen, the friend is met on arrival',
      (tester) async {
    await open(tester, friends: recognition(), meet: 'Sam');
    expect(speaker.words.last, friendConsentQuestion('Sam'));
    mic.say(const NotHeard(VoiceInputFailure.nothingHeard));
    await settle(tester);
  });

  testWidgets('recognition off: how to turn it on', (tester) async {
    await open(tester);
    expect(scan.watch, isNull, reason: 'no faces looked at without consent');
    await say(tester, 'hello friend sam');
    expect(speaker.words.last, kFacesOffPhrase);
    await say(tester, 'who is here');
    expect(speaker.words.last, kFacesOffPhrase);
  });

  testWidgets('no face models on this phone: said, not pretended', (tester) async {
    await open(tester, friends: recognition(), modelsLoad: false);
    await say(tester, 'hello friend sam');
    expect(speaker.words.last, kFacesUnavailablePhrase);
  });

  testWidgets('who is here, and forgetting', (tester) async {
    store.saved['u1'] = [sam];
    await open(tester, friends: recognition());
    now = t0.add(const Duration(seconds: 1));
    scan.watch!.onFaces([seen(samFace)]);
    await say(tester, 'who is here');
    expect(speaker.words.last, 'Sam is here.');

    await say(tester, 'forget sam');
    expect(speaker.words.last, startsWith('Forget Sam?'));
    mic.say(const Heard('yes'));
    await settle(tester);
    expect(speaker.words.last, 'Sam is forgotten.');
    expect(store.saved['u1'], isEmpty);
  });
}
