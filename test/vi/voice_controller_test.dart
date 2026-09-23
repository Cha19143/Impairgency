import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/core/sos/sos_countdown.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/voice/listening_policy.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/core/voice/voice_commands.dart';
import 'package:impairgency/vi/screens/dashboard_screen.dart';
import 'package:impairgency/vi/screens/sos_countdown_screen.dart';
import 'package:impairgency/vi/voice_actions.dart';
import 'package:impairgency/vi/voice_controller.dart';
import 'package:impairgency/vi/voice_targets.dart';
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
    ListenKind kind = ListenKind.command,
    void Function(String partial)? onPartial,
    bool Function(String partial)? settleOn,
    void Function()? onListening,
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

/// Opens a fresh session for every listen, so a test can see how many were
/// opened and finish each one itself.
class SessionRecognizer implements SpeechRecognizer {
  final sessions = <Completer<VoiceHearing>>[];
  int cancels = 0;

  @override
  Future<RecognizerReadiness> prepare() async => RecognizerReadiness.ready;

  @override
  Future<VoiceHearing> listen({
    Duration listenFor = kListenWindow,
    Duration pauseFor = kPauseEndsPhrase,
    ListenKind kind = ListenKind.command,
    void Function(String partial)? onPartial,
    bool Function(String partial)? settleOn,
    void Function()? onListening,
  }) {
    final session = Completer<VoiceHearing>();
    sessions.add(session);
    return session.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    for (final s in sessions) {
      if (!s.isCompleted) s.complete(const NotHeard(VoiceInputFailure.failed));
    }
  }

  bool get open => sessions.isNotEmpty && !sessions.last.isCompleted;
}

/// Behaves like the platform recogniser with partial results: each window
/// hears what the test says a word at a time, and ends early when the
/// controller's hot-word check says so.
class PartialRecognizer implements SpeechRecognizer {
  final sessions = <Completer<VoiceHearing>>[];
  bool Function(String partial)? _settleOn;

  bool get open => sessions.isNotEmpty && !sessions.last.isCompleted;

  @override
  Future<RecognizerReadiness> prepare() async => RecognizerReadiness.ready;

  @override
  Future<VoiceHearing> listen({
    Duration listenFor = kListenWindow,
    Duration pauseFor = kPauseEndsPhrase,
    ListenKind kind = ListenKind.command,
    void Function(String partial)? onPartial,
    bool Function(String partial)? settleOn,
    void Function()? onListening,
  }) {
    _settleOn = settleOn;
    final session = Completer<VoiceHearing>();
    sessions.add(session);
    return session.future;
  }

  /// A partial result arrives.
  void partial(String words) {
    if (!open) return;
    if (_settleOn?.call(words) ?? false) sessions.last.complete(Heard(words));
  }

  /// The phrase ends.
  void finish(String words) {
    if (open) sessions.last.complete(Heard(words));
  }

  @override
  Future<void> cancel() async {
    for (final s in sessions) {
      if (!s.isCompleted) s.complete(const NotHeard(VoiceInputFailure.failed));
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
  SpeechRecognizer recognizer,
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
      onNavigate: routes?.add,
    );

Future<({LocationAvailability availability, String? summary})> _noFix() async =>
    (availability: LocationAvailability.denied, summary: null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('who gets the microphone', () {
    test('a tap takes over listening the app started by itself', () async {
      // The dashboard opens the microphone after its prompt. A tap in that
      // window used to close it without a word - "Tap to speak does nothing".
      final r = SessionRecognizer();
      final speaker = RecordingSpeaker();
      final routes = <String>[];
      final c = controller(r, speaker, routes: routes);

      unawaited(c.listen(auto: true, silenceSpeaker: false));
      await pumpEventQueue();
      expect(c.isAutoListening, isTrue);

      final tap = VoiceMicButton.tap(c);
      await pumpEventQueue();
      expect(speaker.said, contains('Listening.'));
      expect(r.sessions, hasLength(2));
      expect(c.isBusy, isTrue);
      expect(c.isAutoListening, isFalse);

      r.sessions.last.complete(const Heard('scan'));
      await tap;
      expect(routes, [Routes.scan]);
    });

    test('a tap while the user is listening stops it, and says so', () async {
      final r = SessionRecognizer();
      final speaker = RecordingSpeaker();
      final c = controller(r, speaker);
      unawaited(c.listen());
      await pumpEventQueue();

      await VoiceMicButton.tap(c);
      expect(c.phase, VoicePhase.idle);
      expect(speaker.said.last, 'Stopped listening.');
    });

    test("the app's own listening never takes over from a tap", () async {
      final r = SessionRecognizer();
      final c = controller(r, RecordingSpeaker());
      unawaited(c.listen());
      await pumpEventQueue();

      await c.listen(auto: true);
      expect(r.sessions, hasLength(1));
      expect(r.open, isTrue);
    });

    test('the SOS countdown outranks whatever is listening', () async {
      final r = SessionRecognizer();
      final c = controller(r, RecordingSpeaker());
      unawaited(c.listen());
      await pumpEventQueue();

      unawaited(c.listen(
        only: kCancellationCommands,
        dispatch: false,
        auto: true,
        silenceSpeaker: false,
        preempt: true,
      ));
      await pumpEventQueue();
      expect(r.sessions, hasLength(2));
      expect(r.open, isTrue);
    });

    test('the countdown does not hear itself say "cancel"', () async {
      final r = SessionRecognizer();
      final speaker = RecordingSpeaker();
      final c = controller(r, speaker);
      final heard = <VoiceCommand>[];
      c.commands.listen(heard.add);

      final listening = c.listen(
        only: kCancellationCommands,
        dispatch: false,
        auto: true,
        silenceSpeaker: false,
        echoOf: () => ['Say cancel, or touch the screen anywhere, to stop this.'],
      );
      await pumpEventQueue();
      r.sessions.last
          .complete(const Heard('say cancel or touch the screen anywhere'));
      await listening;
      await pumpEventQueue();

      expect(heard, isEmpty);
      expect(speaker.said, isEmpty,
          reason: 'nothing is said over the top of the countdown');
    });
  });

  group('a hot word on a partial result', () {
    final countdown = [
      for (var s = 3; s >= 0; s--) armingAnnouncement(s, contactName: 'Mum'),
      ...kArmingHintLines,
    ];

    Future<ListenOutcome> listenForCancel(VoiceController c) => c.listen(
          only: kCancellationCommands,
          dispatch: false,
          auto: true,
          silenceSpeaker: false,
          preempt: true,
          settleEarly: true,
          echoOf: () => countdown,
        );

    test('a partial cancel is acted on before the phrase ends', () async {
      final r = PartialRecognizer();
      final c = controller(r, RecordingSpeaker());
      final heard = <VoiceCommand>[];
      c.commands.listen(heard.add);

      final listening = listenForCancel(c);
      await pumpEventQueue();
      r.partial('calling mum in 2');
      expect(r.open, isTrue);
      r.partial('calling mum in 2 teka');

      expect(await listening, ListenOutcome.acted);
      await pumpEventQueue();
      expect(heard, [VoiceCommand.cancel]);
    });

    test('a partial cancel or stop settles at once', () async {
      // The testers said "cancel" and "stop" and the call went ahead. The
      // hint was one sentence with both words in the middle of it, so a
      // partial "cancel" might still have been the app, and waited for the
      // phrase to end - past the end of a three-second countdown. "Say
      // cancel." ends on the word, and "stop" is not said at all.
      for (final word in ['cancel', 'stop']) {
        final r = PartialRecognizer();
        final c = controller(r, RecordingSpeaker());
        final heard = <VoiceCommand>[];
        c.commands.listen(heard.add);

        final listening = listenForCancel(c);
        await pumpEventQueue();
        r.partial(word);

        expect(await listening, ListenOutcome.acted, reason: word);
        await pumpEventQueue();
        expect(heard, [VoiceCommand.cancel], reason: word);
      }
    });

    test('a partial ending in a word the app is saying waits for the phrase',
        () async {
      // "Or touch the screen anywhere." - a partial ending in "touch" may
      // yet be that sentence. Not a command either way, but a cancel word
      // in front of it must not be taken from the app.
      final r = PartialRecognizer();
      final c = controller(r, RecordingSpeaker());
      final heard = <VoiceCommand>[];
      c.commands.listen(heard.add);

      final listening = listenForCancel(c);
      await pumpEventQueue();
      r.partial('say cancel or touch');
      await pumpEventQueue();
      expect(r.open, isTrue, reason: 'not settled on the partial');

      r.finish('say cancel or touch the screen anywhere cancel');
      expect(await listening, ListenOutcome.acted);
      await pumpEventQueue();
      expect(heard, [VoiceCommand.cancel], reason: 'the last word is the user');
    });

    test("the app's own sentence never settles a window", () async {
      final r = PartialRecognizer();
      final c = controller(r, RecordingSpeaker());
      final heard = <VoiceCommand>[];
      c.commands.listen(heard.add);

      final listening = listenForCancel(c);
      await pumpEventQueue();
      r.partial('say cancel');
      r.partial('say cancel or touch');
      await pumpEventQueue();
      expect(r.open, isTrue);

      r.finish('say cancel or touch the screen anywhere');
      expect(await listening, ListenOutcome.nothingHeard);
      expect(heard, isEmpty);
    });
  });

  group('buttons, by name', () {
    // The testers asked for every button to work by voice.
    test('a button is pressed by saying its name', () async {
      final r = SessionRecognizer();
      final speaker = RecordingSpeaker();
      final c = controller(r, speaker);
      var pressed = 0;
      c.targets.register(VoiceTarget('Saved places', () => pressed++));

      final listening = c.listen();
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('open saved places'));

      expect(await listening, ListenOutcome.acted);
      expect(pressed, 1);
      expect(speaker.said, ['Saved places.'], reason: 'heard to have happened');
    });

    test('a command said on its own is still the command', () async {
      // Scan's Back asks first; its button may not. The command decides.
      final r = SessionRecognizer();
      final routes = <String>[];
      final c = controller(r, RecordingSpeaker(), routes: routes);
      var pressed = 0;
      c.targets.register(VoiceTarget('Scan', () => pressed++));

      final listening = c.listen();
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('scan'));
      await listening;

      expect(routes, [Routes.scan]);
      expect(pressed, 0);
    });

    test('a button named in full outranks a command that shares a word',
        () async {
      // "location" is a word for "where am I". "Share my location" is not.
      final r = SessionRecognizer();
      final speaker = RecordingSpeaker();
      final c = controller(r, speaker);
      var pressed = 0;
      c.targets.register(VoiceTarget('Share my location', () => pressed++));

      final listening = c.listen();
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('share my location'));
      await listening;

      expect(pressed, 1);
      expect(c.lastCommand, isNull);
    });

    test('a button named exactly wins, even with help in its name',
        () async {
      // Saying the Settings button "Emergency contacts" started an SOS.
      final r = SessionRecognizer();
      final routes = <String>[];
      final c = controller(r, RecordingSpeaker(), routes: routes);
      var pressed = 0;
      c.targets.register(VoiceTarget('Emergency contacts', () => pressed++));

      final listening = c.listen();
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('emergency contacts'));
      await listening;

      expect(pressed, 1);
      expect(routes, isEmpty);
    });

    test('help said on its own is help, whatever button shares the word',
        () async {
      final r = SessionRecognizer();
      final routes = <String>[];
      final c = controller(r, RecordingSpeaker(), routes: routes);
      var pressed = 0;
      c.targets
        ..register(VoiceTarget('Help me choose', () => pressed++))
        ..register(VoiceTarget('Help', () => pressed++));

      for (final said in ['help', 'help me choose a place']) {
        final listening = c.listen();
        await pumpEventQueue();
        r.sessions.last.complete(Heard(said));
        await listening;
      }

      expect(pressed, 0);
      expect(routes, [Routes.sos, Routes.sos]);
    });

    test('in a window the app opened, help is a short phrase', () async {
      // Hands-free heard "I need help finding the settings" from across the
      // room and started an emergency.
      final r = SessionRecognizer();
      final routes = <String>[];
      final c = controller(r, RecordingSpeaker(), routes: routes);

      for (final said in [
        'i need help finding the settings',
        'i do not need help',
        'hindi ko kailangan ng tulong',
      ]) {
        final listening = c.listen(auto: true, quiet: true);
        await pumpEventQueue();
        r.sessions.last.complete(Heard(said));
        await listening;
      }
      expect(routes, isEmpty);

      for (final said in ['help', 'help me', 'tulong po', 'please help me']) {
        final listening = c.listen(auto: true, quiet: true);
        await pumpEventQueue();
        r.sessions.last.complete(Heard(said));
        await listening;
      }
      expect(routes, List.filled(4, Routes.sos));
    });

    test('a tap is not held to that: pressing the button and saying help '
        'means it', () async {
      final r = SessionRecognizer();
      final routes = <String>[];
      final c = controller(r, RecordingSpeaker(), routes: routes);

      final listening = c.listen();
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('i need help finding the settings'));
      await listening;
      expect(routes, [Routes.sos]);
    });

    test('with a screen reader on, labels it reads out are not the user',
        () async {
      final r = SessionRecognizer();
      final routes = <String>[];
      var reader = true;
      final c = VoiceController(
        recognizer: r,
        speaker: RecordingSpeaker(),
        actions: () =>
            const VoiceActions(location: _NoLocation(), fetchFix: _noFix),
        onNavigate: routes.add,
        screenReaderOn: () => reader,
        wait: (_) async {},
      );
      var pressed = 0;
      c.targets.register(VoiceTarget('Emergency SOS', () => pressed++));

      Future<void> hear(String said) async {
        final listening = c.listen(auto: true, quiet: true);
        await pumpEventQueue();
        r.sessions.last.complete(Heard(said));
        await listening;
      }

      await hear('emergency sos button');
      expect(routes, isEmpty, reason: 'TalkBack reading the button');
      expect(pressed, 0);

      reader = false;
      await hear('emergency sos');
      expect(pressed, 1);
    });

    test('two buttons that both match are asked about', () async {
      final r = SessionRecognizer();
      final speaker = RecordingSpeaker();
      final c = controller(r, speaker);
      final pressed = <String>[];
      c.targets
        ..register(VoiceTarget('Call Mum work', () => pressed.add('work')))
        ..register(VoiceTarget('Call Mum mobile', () => pressed.add('mobile')));

      final listening = c.listen();
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('call mum mobile work'));
      await pumpEventQueue();
      expect(speaker.said.last, 'Did you mean Call Mum work, or Call Mum mobile?');
      expect(pressed, isEmpty);

      r.sessions.last.complete(const Heard('mobile'));
      expect(await listening, ListenOutcome.acted);
      expect(pressed, ['mobile']);
    });

    test('an answer that picks neither presses nothing, and says so', () async {
      final r = SessionRecognizer();
      final speaker = RecordingSpeaker();
      final c = controller(r, speaker);
      final pressed = <String>[];
      c.targets
        ..register(VoiceTarget('Call Mum work', () => pressed.add('work')))
        ..register(VoiceTarget('Call Mum mobile', () => pressed.add('mobile')));

      final listening = c.listen();
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('call mum mobile work'));
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('the bakery'));
      await listening;

      expect(pressed, isEmpty);
      expect(speaker.said.last, 'Nothing was pressed.');
    });

    test('the countdown window never presses buttons', () async {
      final r = SessionRecognizer();
      final c = controller(r, RecordingSpeaker());
      var pressed = 0;
      c.targets.register(VoiceTarget('Cancel', () => pressed++));
      final heard = <VoiceCommand>[];
      c.commands.listen(heard.add);

      final listening = c.listen(
        only: kCancellationCommands,
        dispatch: false,
        auto: true,
        silenceSpeaker: false,
        preempt: true,
      );
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('cancel'));
      await listening;
      await pumpEventQueue();

      expect(pressed, 0);
      expect(heard, [VoiceCommand.cancel]);
    });

    test("the last screen's buttons are not pressed from the next", () async {
      // Its Back is still mounted for a frame after the next screen opens.
      final r = SessionRecognizer();
      final c = controller(r, RecordingSpeaker())..routeChanged(Routes.settings);
      var pressed = 0;
      c.targets.register(VoiceTarget('Saved places', () => pressed++));
      c.routeChanged(Routes.home);

      final listening = c.listen();
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('saved places'));
      expect(await listening, ListenOutcome.notUnderstood);
      expect(pressed, 0);
    });
  });

  group('dictation', () {
    late SessionRecognizer r;
    late RecordingSpeaker speaker;
    late VoiceController c;

    setUp(() {
      r = SessionRecognizer();
      speaker = RecordingSpeaker();
      c = controller(r, speaker);
    });

    Future<void> say(String words) async {
      r.sessions.last.complete(Heard(words));
      await pumpEventQueue();
    }

    Future<void> silence() async {
      r.sessions.last.complete(const NotHeard(VoiceInputFailure.nothingHeard));
      await pumpEventQueue();
    }

    test('reads back what it heard, and keeps it on done', () async {
      final kept =
          c.dictate(label: 'Phone number', shape: DictationShape.phone);
      await pumpEventQueue();
      expect(speaker.said.last, 'Say the phone number.');

      await say('zero nine one seven one two three four five six seven');
      expect(speaker.said.last,
          'Phone number: 0 9 1, 7 1 2, 3 4 5, 6 7. Say done to keep it, add '
          'and more, delete last word, spell it, or say it again.');

      await say('done');
      expect(await kept, '09171234567');
      expect(speaker.said.last, 'Phone number kept.');
    });

    test('"correct" and "tama" keep it; they are not the new value', () async {
      for (final word in ['correct', 'tama', "yes that's right"]) {
        final kept = c.dictate(label: 'Name', shape: DictationShape.name);
        await pumpEventQueue();
        await say('ana');
        await say(word);
        expect(await kept, 'Ana', reason: word);
      }
    });

    test('anything else is the answer said again, and is read back in turn',
        () async {
      final kept = c.dictate(label: 'Email address', shape: DictationShape.email);
      await pumpEventQueue();
      await say('ana at gmail dot com');
      // A "no" inside a longer answer is part of the answer.
      await say('no reply at gmail dot com');
      expect(speaker.said.last,
          startsWith('Email address: n o r e p l y at gmail'));
      await say('okay');
      expect(await kept, 'noreply@gmail.com');
    });

    test('add, delete last word, spell, and done', () async {
      final kept = c.dictate(label: 'Email address', shape: DictationShape.email);
      await pumpEventQueue();
      await say('ana at yahoo');
      await say('add dot com');
      expect(speaker.said.last, startsWith('Email address: a n a at yahoo dot com.'));
      await say('delete last word');
      expect(speaker.said.last, startsWith('Email address: a n a at yahoo dot.'));
      await say('spell it');
      expect(speaker.said.last, contains('letter by letter'));
      await say('c o m');
      await say('done');
      expect(await kept, 'ana@yahoo.com');
    });

    test('an address that is not complete is not kept', () async {
      final kept = c.dictate(label: 'Email address', shape: DictationShape.email);
      await pumpEventQueue();
      await say('ana at yahoo');
      expect(speaker.said.last, contains('not a complete email address yet'));
      await say('done');
      expect(speaker.said.last, startsWith('That is not a complete email address'));
      await say('add dot com');
      await say('done');
      expect(await kept, 'ana@yahoo.com');
    });

    test('read back, clear, and no', () async {
      final kept = c.dictate(label: 'Name', shape: DictationShape.name);
      await pumpEventQueue();
      await say('ana cruz');
      await say('read it back');
      expect(speaker.said.last, 'Name: Ana Cruz. Say done, or change it.');
      await say('start over');
      expect(speaker.said.last, 'Cleared. Say the name.');
      await say('ben');
      await say('no');
      expect(speaker.said.last, 'Say the name again.');
      await say('lea');
      await say('done');
      expect(await kept, 'Lea');
    });

    test('cancel leaves the field as it was', () async {
      final kept = c.dictate(label: 'Name', shape: DictationShape.name);
      await pumpEventQueue();
      await say('ana');
      await say('cancel');
      expect(await kept, isNull);
      expect(speaker.said.last, 'The name was left as it was.');
    });

    test('silence asks again, and three leave the field as it was', () async {
      final kept = c.dictate(label: 'Name');
      await pumpEventQueue();
      await silence();
      expect(speaker.said.last, startsWith('I did not hear anything.'));
      await silence();
      await silence();
      expect(await kept, isNull);
    });

    test('what the field held is added to, and never lost to silence',
        () async {
      final kept = c.dictate(
          label: 'Name', shape: DictationShape.name, initial: 'Ana');
      await pumpEventQueue();
      await silence();
      expect(speaker.said.last, contains('Name: Ana.'));
      await say('add cruz');
      await say('done');
      expect(await kept, 'Ana Cruz');
    });

    test('a dictation window is long, and tells the recogniser so', () async {
      final heard = <(Duration, ListenKind)>[];
      final c2 = controller(_Recording(r, heard), speaker);
      final kept = c2.dictate(label: 'Name');
      await pumpEventQueue();
      await say('ana');
      await say('done');
      await kept;
      expect(heard.first, (kDictationWindow, ListenKind.dictation));
    });

    test('never presses a button, or acts on a command', () async {
      final routes = <String>[];
      final c2 = controller(r, speaker, routes: routes);
      var pressed = 0;
      c2.targets.register(VoiceTarget('Scan', () => pressed++));

      final kept = c2.dictate(label: 'Place name');
      await pumpEventQueue();
      await say('scan');
      await say('yes');

      expect(await kept, 'scan');
      expect(pressed, 0);
      expect(routes, isEmpty);
    });

    test('the microphone opening is felt, for a question the app asked',
        () async {
      var buzzes = 0;
      final c2 = VoiceController(
        recognizer: _Opening(r),
        speaker: speaker,
        actions: () =>
            const VoiceActions(location: _NoLocation(), fetchFix: _noFix),
        listeningCue: () => buzzes++,
      );
      final kept = c2.dictate(label: 'Name');
      await pumpEventQueue();
      expect(buzzes, 1);
      await say('ana');
      await say('done');
      await kept;

      // A hands-free window, opened again and again, does not buzz.
      final listening = c2.listen(auto: true, quiet: true);
      await pumpEventQueue();
      await say('the weather');
      await listening;
      expect(buzzes, 2, reason: 'two prompts, no hands-free window');
    });
  });

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

    testWidgets(
        "leaving the dashboard does not cancel the next screen's listening",
        (tester) async {
      // The dashboard's dispose() stopped the app-wide microphone - about half
      // a second after the SOS countdown had opened it for "cancel".
      final r = SessionRecognizer();
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
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: SosCountdownScreen(
          onFire: () {},
          onCancel: () {},
          startListening: () => c.listen(
            only: kCancellationCommands,
            dispatch: false,
            auto: true,
            silenceSpeaker: false,
            preempt: true,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));

      expect(r.open, isTrue, reason: 'still listening for cancel');
      expect(c.isBusy, isTrue);
      await tester.pumpWidget(const SizedBox());
      await c.stop();
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

  group('round 4: hands-free answers', () {
    test('"stop" on its own stops the app talking, and says nothing', () async {
      final r = SessionRecognizer();
      final speaker = RecordingSpeaker();
      final c = controller(r, speaker);
      final listening = c.listen(auto: true, quiet: true);
      await pumpEventQueue();
      r.sessions.last.complete(const Heard('stop'));
      await listening;
      expect(speaker.stops, greaterThan(0));
      expect(speaker.said, isEmpty);
    });

    test('a near miss is answered once in 20 seconds, and not for the same '
        'words twice', () async {
      final r = SessionRecognizer();
      final speaker = RecordingSpeaker();
      var now = DateTime(2026, 9, 18, 10);
      final c = VoiceController(
        recognizer: r,
        speaker: speaker,
        actions: () =>
            const VoiceActions(location: _NoLocation(), fetchFix: _noFix),
        now: () => now,
      );

      Future<void> hear(String words) async {
        final listening = c.listen(auto: true, quiet: true);
        await pumpEventQueue();
        r.sessions.last.complete(Heard(words));
        await listening;
      }

      await hear('arround here');
      expect(speaker.said.single, startsWith('I heard "arround here"'));

      now = now.add(const Duration(seconds: 5));
      await hear('arround me');
      expect(speaker.said, hasLength(1), reason: 'within 20 seconds');

      now = now.add(const Duration(seconds: 30));
      await hear('arround here');
      await hear('did you remember the bread');
      expect(speaker.said, hasLength(1),
          reason: 'the same words again, then chatter');

      await hear('arround me');
      expect(speaker.said, hasLength(2));
    });
  });
}

/// Passes everything to [inner], noting each window's length and kind.
class _Recording implements SpeechRecognizer {
  _Recording(this.inner, this.heard);
  final SpeechRecognizer inner;
  final List<(Duration, ListenKind)> heard;

  @override
  Future<RecognizerReadiness> prepare() => inner.prepare();

  @override
  Future<VoiceHearing> listen({
    Duration listenFor = kListenWindow,
    Duration pauseFor = kPauseEndsPhrase,
    ListenKind kind = ListenKind.command,
    void Function(String partial)? onPartial,
    bool Function(String partial)? settleOn,
    void Function()? onListening,
  }) {
    heard.add((listenFor, kind));
    return inner.listen(listenFor: listenFor, pauseFor: pauseFor);
  }

  @override
  Future<void> cancel() => inner.cancel();
}

/// Says the microphone is open as soon as it is asked to open.
class _Opening implements SpeechRecognizer {
  _Opening(this.inner);
  final SpeechRecognizer inner;

  @override
  Future<RecognizerReadiness> prepare() => inner.prepare();

  @override
  Future<VoiceHearing> listen({
    Duration listenFor = kListenWindow,
    Duration pauseFor = kPauseEndsPhrase,
    ListenKind kind = ListenKind.command,
    void Function(String partial)? onPartial,
    bool Function(String partial)? settleOn,
    void Function()? onListening,
  }) {
    onListening?.call();
    return inner.listen(listenFor: listenFor, pauseFor: pauseFor);
  }

  @override
  Future<void> cancel() => inner.cancel();
}
