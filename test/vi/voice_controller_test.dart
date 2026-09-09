import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/core/voice/voice_commands.dart';
import 'package:impairgency/vi/screens/dashboard_screen.dart';
import 'package:impairgency/vi/screens/sos_countdown_screen.dart';
import 'package:impairgency/vi/voice_actions.dart';
import 'package:impairgency/vi/voice_controller.dart';
import 'package:impairgency/vi/widgets/voice_mic_button.dart';

class RecordingSpeaker implements Speaker {
  final List<String> said = [];
  int stops = 0;

  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;
  @override
  Future<void> repeat() async {
    said.add('(repeat) ${lastSpoken ?? kNothingToRepeat}');
  }

  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);
  @override
  Future<void> stop() async => stops++;
}

/// A recogniser the test scripts: what permission says, then what is heard.
class FakeRecognizer implements SpeechRecognizer {
  FakeRecognizer({
    this.readiness = RecognizerReadiness.ready,
    this.hearing = const NotHeard(VoiceInputFailure.nothingHeard),
  });

  RecognizerReadiness readiness;
  VoiceHearing hearing;
  int prepares = 0;
  int listens = 0;
  int cancels = 0;

  /// When set, [listen] waits for it, so a test can observe "Listening…".
  Completer<VoiceHearing>? hold;

  @override
  Future<RecognizerReadiness> prepare() async {
    prepares++;
    return readiness;
  }

  @override
  Future<VoiceHearing> listen({
    Duration listenFor = kListenWindow,
    Duration pauseFor = kPauseEndsPhrase,
    void Function(String partial)? onPartial,
  }) async {
    listens++;
    final held = hold;
    if (held != null) return held.future;
    return hearing;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    final held = hold;
    if (held != null && !held.isCompleted) {
      held.complete(const NotHeard(VoiceInputFailure.failed));
    }
  }
}

class _NoLocation implements LocationSource {
  const _NoLocation();
  @override
  Future<LocationAvailability> availability() async =>
      LocationAvailability.denied;
  @override
  Future<LocationAvailability> requestPermission() async =>
      LocationAvailability.denied;
  @override
  Future<LocationFix?> currentFix({Duration timeout = Duration.zero}) async =>
      null;
  @override
  Future<LocationFix?> lastKnownFix() async => null;
}

VoiceController controller(
  FakeRecognizer recognizer,
  RecordingSpeaker speaker, {
  List<String>? routes,
}) =>
    VoiceController(
      recognizer: recognizer,
      speaker: speaker,
      actions: () => const VoiceActions(
        location: _NoLocation(),
        fetchFix: _noFix,
        contactName: 'Mum',
      ),
      onNavigate: routes == null ? null : routes.add,
    );

Future<({LocationAvailability availability, String? summary})> _noFix() async =>
    (availability: LocationAvailability.denied, summary: null);

void main() {
  group('the path from microphone to action', () {
    test('a spoken command is acted on and goes somewhere', () async {
      final speaker = RecordingSpeaker();
      final routes = <String>[];
      final c = controller(
        FakeRecognizer(hearing: const Heard('help me please')),
        speaker,
        routes: routes,
      );

      await c.listen();

      expect(c.lastCommand, VoiceCommand.help);
      expect(speaker.said, contains('Calling for help.'));
      expect(routes, [Routes.sos]);
      expect(c.phase, VoicePhase.idle, reason: 'ready for the next one');
    });

    test('the app stops talking before it listens', () async {
      final speaker = RecordingSpeaker();
      final c = controller(FakeRecognizer(hearing: const Heard('scan')), speaker);
      await c.listen();
      expect(speaker.stops, greaterThan(0));
    });

    test('the SOS countdown keeps talking while it listens for cancel',
        () async {
      final speaker = RecordingSpeaker();
      final c = controller(FakeRecognizer(hearing: const Heard('cancel')), speaker);
      final heard = <VoiceCommand>[];
      c.commands.listen(heard.add);

      await c.listen(
        only: kCancellationCommands,
        dispatch: false,
        silenceSpeaker: false,
      );
      await Future<void>.delayed(Duration.zero);

      expect(speaker.stops, 0);
      expect(heard, [VoiceCommand.cancel]);
      expect(speaker.said, isNot(contains('There is nothing to cancel.')),
          reason: 'the screen acts on it, not the default handler');
    });

    test('repeat goes to the speaker rather than inventing words', () async {
      final speaker = RecordingSpeaker()..said.add('Path looks clear');
      final c = controller(FakeRecognizer(hearing: const Heard('again')), speaker);
      await c.listen();
      expect(speaker.said.last, '(repeat) Path looks clear');
    });
  });

  group('every failure is said out loud, and shown', () {
    for (final (readiness, expected) in [
      (RecognizerReadiness.microphoneDenied, 'microphone is off'),
      (RecognizerReadiness.microphoneBlocked, 'Settings'),
      (RecognizerReadiness.unavailable, 'not available on this phone'),
    ]) {
      test('$readiness', () async {
        final speaker = RecordingSpeaker();
        final r = FakeRecognizer(readiness: readiness);
        final c = controller(r, speaker);

        await c.listen();

        expect(c.phase, VoicePhase.failed);
        expect(c.failureMessage, contains(expected));
        expect(speaker.said.single, c.failureMessage,
            reason: 'what is shown is what is said');
        expect(speaker.said.single, contains('buttons still work'));
        expect(r.listens, 0, reason: 'never opens a microphone it cannot use');
      });
    }

    test('words that are not a command say what was heard and what to say',
        () async {
      final speaker = RecordingSpeaker();
      final c = controller(
          FakeRecognizer(hearing: const Heard('open the pod bay doors')),
          speaker);
      await c.listen();

      expect(c.phase, VoicePhase.failed);
      expect(speaker.said.single, contains('open the pod bay doors'));
      expect(speaker.said.single, contains('help'));
      expect(speaker.said.single, contains('scan'));
    });

    test('a listening window that hears nothing says so when the user asked',
        () async {
      final speaker = RecordingSpeaker();
      final c = controller(FakeRecognizer(), speaker);
      await c.listen();
      expect(speaker.said.single, contains('did not hear anything'));
    });

    test('but stays quiet about silence when the app was listening on its own',
        () async {
      // After "Say scan, navigate, or help", not answering is a choice.
      final speaker = RecordingSpeaker();
      final c = controller(FakeRecognizer(), speaker);
      await c.listen(auto: true);
      expect(speaker.said, isEmpty);
      expect(c.phase, VoicePhase.idle);
    });

    test('a blocked microphone is explained once when automatic, always when tapped',
        () async {
      final speaker = RecordingSpeaker();
      final c = controller(
          FakeRecognizer(readiness: RecognizerReadiness.microphoneBlocked),
          speaker);
      await c.listen(auto: true);
      await c.listen(auto: true);
      expect(speaker.said, hasLength(1), reason: 'not nagged on every screen');
      expect(c.phase, VoicePhase.failed, reason: 'still visible');

      await c.listen();
      expect(speaker.said, hasLength(2), reason: 'a tap always gets an answer');
    });

    test('network failures are named as such', () async {
      final speaker = RecordingSpeaker();
      final c = controller(
          FakeRecognizer(hearing: const NotHeard(VoiceInputFailure.network)),
          speaker);
      await c.listen();
      expect(speaker.said.single, contains('connection'));
    });
  });

  group('stopping', () {
    test('stop abandons the attempt and nothing is acted on', () async {
      final speaker = RecordingSpeaker();
      final r = FakeRecognizer()..hold = Completer<VoiceHearing>();
      final routes = <String>[];
      final c = controller(r, speaker, routes: routes);

      final attempt = c.listen();
      await Future<void>.delayed(Duration.zero);
      expect(c.phase, VoicePhase.listening);

      await c.stop();
      // The fake completes the held window on cancel; a real recogniser may
      // still deliver words afterwards, which is what the guard is for.
      if (!r.hold!.isCompleted) r.hold!.complete(const Heard('help'));
      await attempt;

      expect(r.cancels, 1);
      expect(routes, isEmpty);
      expect(c.phase, VoicePhase.idle);
    });

    test('listening twice at once is one attempt', () async {
      final r = FakeRecognizer()..hold = Completer<VoiceHearing>();
      final c = controller(r, RecordingSpeaker());
      final first = c.listen();
      final second = c.listen();
      await Future<void>.delayed(Duration.zero);
      r.hold!.complete(const Heard('scan'));
      await first;
      await second;
      expect(r.listens, 1);
    });
  });

  group('the microphone button', () {
    Widget host(Widget child) => MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: child),
        );

    testWidgets('says what it is doing at each stage', (tester) async {
      final r = FakeRecognizer()..hold = Completer<VoiceHearing>();
      final c = controller(r, RecordingSpeaker());
      await tester.pumpWidget(host(VoiceMicButton(controller: c)));

      expect(find.text('Tap to speak'), findsOneWidget);
      await tester.tap(find.text('Tap to speak'));
      await tester.pump();
      expect(find.text('Listening…'), findsOneWidget);

      r.hold!.complete(const Heard('scan'));
      await tester.pumpAndSettle();
      expect(find.text('Tap to speak'), findsOneWidget);
    });

    testWidgets('a failure is written on the screen, not only spoken',
        (tester) async {
      final c = controller(
          FakeRecognizer(readiness: RecognizerReadiness.microphoneBlocked),
          RecordingSpeaker());
      await tester.pumpWidget(host(VoiceMicButton(controller: c)));
      await tester.tap(find.text('Tap to speak'));
      await tester.pumpAndSettle();

      expect(find.textContaining('blocked for ImpairGency'), findsOneWidget);
      expect(find.text('Voice did not work. Tap to try again'), findsOneWidget);
    });

    testWidgets('is big enough to find by sweeping', (tester) async {
      final c = controller(FakeRecognizer(), RecordingSpeaker());
      await tester.pumpWidget(host(VoiceMicButton(controller: c)));
      final size = tester.getSize(find.byType(VoiceMicButton));
      expect(size.height, greaterThanOrEqualTo(88));
    });
  });

  group('where the microphone is wired in', () {
    testWidgets('the dashboard listens after it asks', (tester) async {
      // "Say scan, navigate, or help." was a question nobody was listening
      // to the answer to.
      final r = FakeRecognizer();
      final c = controller(r, RecordingSpeaker());
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: DashboardScreen(
          onScan: () {},
          onAssist: () {},
          onSos: () {},
          onWhatCanISay: () {},
          onSettings: () {},
          voice: c,
        ),
      ));
      await tester.pumpAndSettle();

      expect(r.listens, 1);
      expect(find.byType(VoiceMicButton), findsOneWidget);
    });

    testWidgets('the SOS countdown opens the microphone for "cancel"',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: SosCountdownScreen(
          onFire: () {},
          onCancel: () {},
          startListening: () => opened++,
        ),
      ));
      await tester.pump();
      expect(opened, 1);
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
