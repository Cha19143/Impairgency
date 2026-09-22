import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/speech/speech_queue.dart';
import 'package:impairgency/core/voice/listening_policy.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/core/voice/voice_commands.dart';
import 'package:impairgency/vi/voice_controller.dart';

import 'voice_fakes.dart';

VoiceController controller(
  OpenWindows windows,
  Speaker speaker, {
  List<String>? routes,
}) =>
    voiceControllerFor(windows, speaker, routes: routes);

void main() {
  test('with hands-free on, the microphone reopens after every phrase', () async {
    // The testers asked not to have to press "Tap to speak".
    final windows = OpenWindows();
    final c = controller(windows, Recording())..handsFree = true;
    c.attach(const VoiceScope());
    await pumpEventQueue();
    expect(windows.open, isTrue);

    await windows.hear(const NotHeard(VoiceInputFailure.nothingHeard));
    expect(windows.sessions, hasLength(2));
    expect(windows.open, isTrue);

    await windows.hear(const Heard('the weather is nice today'));
    expect(windows.sessions, hasLength(3), reason: 'chatter is not a reason to stop');
    expect(windows.open, isTrue);
    c.handsFree = false;
    await pumpEventQueue();
  });

  test('with hands-free off, nothing listens without a tap', () async {
    final windows = OpenWindows();
    final c = controller(windows, Recording());
    c.attach(const VoiceScope());
    await pumpEventQueue();
    expect(windows.sessions, isEmpty);
  });

  test('background conversation is not answered out loud', () async {
    final windows = OpenWindows();
    final speaker = Recording();
    final c = controller(windows, speaker)..handsFree = true;
    c.attach(const VoiceScope());
    await pumpEventQueue();
    await windows.hear(const Heard('did you remember the bread'));
    expect(speaker.said, [kHandsFreeListening],
        reason: 'only that it is listening, once');
    c.handsFree = false;
    await pumpEventQueue();
  });

  test("a screen's own commands go to the screen first", () async {
    final windows = OpenWindows();
    final routes = <String>[];
    final c = controller(windows, Recording(), routes: routes)..handsFree = true;
    final handled = <VoiceCommand>[];
    c.attach(VoiceScope(
      commands: () => kReadingCommands,
      onCommand: (heard) async {
        if (heard.command != VoiceCommand.pause) return false;
        handled.add(heard.command);
        return true;
      },
    ));
    await pumpEventQueue();

    await windows.hear(const Heard('pause'));
    expect(handled, [VoiceCommand.pause]);
    expect(routes, isEmpty);

    await windows.hear(const Heard('go back'));
    expect(routes, [Routes.home], reason: 'what the screen passes on still works');
    c.handsFree = false;
    await pumpEventQueue();
  });

  test("a screen's reading of the words never gets in the way of help",
      () async {
    final windows = OpenWindows();
    final routes = <String>[];
    final c = controller(windows, Recording(), routes: routes)..handsFree = true;
    final names = <String>[];
    c.attach(VoiceScope(
      commands: () => kAssistCommands,
      onWords: (words) async {
        names.add(words);
        return true;
      },
    ));
    await pumpEventQueue();

    await windows.hear(const Heard('clinic'));
    expect(names, ['clinic']);

    // Short, as help is in a window the app opened by itself.
    await windows.hear(const Heard('tulong po'));
    expect(names, ['clinic'], reason: 'not asked');
    expect(c.lastCommand, VoiceCommand.help);
    expect(routes, [Routes.sos]);
    c.handsFree = false;
    await pumpEventQueue();
  });

  test('the next screen takes over; the last one stops listening', () async {
    final windows = OpenWindows();
    final c = controller(windows, Recording())..handsFree = true;
    c.routeChanged(Routes.home);
    final dashboard = c.attach(const VoiceScope());
    await pumpEventQueue();
    expect(windows.open, isTrue);

    c.routeChanged(Routes.settings); // a screen with no scope
    await pumpEventQueue();
    expect(windows.open, isFalse);
    dashboard.detach(); // its dispose, late
    await pumpEventQueue();
    expect(windows.open, isFalse);

    c.routeChanged(Routes.scan);
    c.attach(VoiceScope(commands: () => kScanCommands));
    await pumpEventQueue();
    expect(windows.open, isTrue);
    c.handsFree = false;
    await pumpEventQueue();
  });

  test('a microphone left open behind another app is closed', () async {
    final windows = OpenWindows();
    final c = controller(windows, Recording())..handsFree = true;
    c.attach(const VoiceScope());
    await pumpEventQueue();

    c.setForeground(false);
    await pumpEventQueue();
    expect(windows.open, isFalse);

    c.setForeground(true);
    await pumpEventQueue();
    expect(windows.open, isTrue);
    c.handsFree = false;
    await pumpEventQueue();
  });

  test('a blocked microphone is explained once, and not asked again', () async {
    final windows = OpenWindows(readiness: RecognizerReadiness.microphoneBlocked);
    final speaker = Recording();
    final c = controller(windows, speaker)..handsFree = true;
    c.attach(const VoiceScope());
    await pumpEventQueue();
    expect(speaker.said.where((s) => s.contains('blocked')), hasLength(1));
    expect(c.isHandsFreeActive, isFalse);
  });

  test('a microphone that keeps failing is given up on, out loud', () async {
    final windows = OpenWindows();
    final speaker = Recording();
    final c = controller(windows, speaker)..handsFree = true;
    c.attach(const VoiceScope());
    await pumpEventQueue();
    for (var i = 0; i < 5; i++) {
      await windows.hear(const NotHeard(VoiceInputFailure.failed));
    }
    expect(speaker.said, contains(kHandsFreeStopped));
    expect(c.isHandsFreeActive, isFalse);
  });

  test('the app is not heard as the user', () async {
    // The dashboard's prompt, heard back through the microphone, contains
    // "scan", "read" and "help". None of them was said by the person.
    final engine = HeldEngine();
    final queue = SpeechQueue(engine: engine, lineGap: Duration.zero);
    final windows = OpenWindows();
    final routes = <String>[];
    final c = controller(windows, queue, routes: routes)..handsFree = true;
    c.attach(const VoiceScope());
    await pumpEventQueue();

    unawaited(queue.speak('Say scan, read, take me to a place, or help.'));
    await pumpEventQueue();
    await windows.hear(const Heard('say scan read take me to a place or help'));
    expect(c.lastCommand, isNull, reason: 'not scan, not read, and not help');
    expect(windows.open, isTrue);

    engine.finish();
    await pumpEventQueue();
    await windows.hear(const Heard('scan'));
    engine.finish(); // "Opening scan."
    await pumpEventQueue();
    expect(routes, [Routes.scan], reason: 'the person saying it still counts');
    c.handsFree = false;
    await pumpEventQueue();
  });

  test('a hazard warning closes the microphone until it has been said', () async {
    final engine = HeldEngine();
    final queue = SpeechQueue(engine: engine, lineGap: Duration.zero);
    final windows = OpenWindows();
    final c = controller(windows, queue)..handsFree = true;
    c.attach(const VoiceScope());
    await pumpEventQueue();
    expect(windows.open, isTrue);

    unawaited(queue.announce('Stop. car right in front of you',
        priority: SpeechPriority.hazard));
    await pumpEventQueue();
    expect(windows.open, isFalse);

    engine.finish();
    await pumpEventQueue();
    expect(windows.open, isTrue);
    c.handsFree = false;
    await pumpEventQueue();
  });

  group('asking', () {
    test('a question hears yes', () async {
      final windows = OpenWindows();
      final speaker = Recording();
      final c = controller(windows, speaker);
      final answer = c.ask('Leave scan? Say yes to leave.');
      await pumpEventQueue();
      expect(speaker.said.last, 'Leave scan? Say yes to leave.');
      await windows.hear(const Heard('opo'));
      expect((await answer)?.command, VoiceCommand.yes);
    });

    test('silence is no answer, and is not scolded', () async {
      final windows = OpenWindows();
      final speaker = Recording();
      final c = controller(windows, speaker);
      final answer = c.ask('Go there?');
      await pumpEventQueue();
      await windows.hear(const NotHeard(VoiceInputFailure.nothingHeard));
      expect(await answer, isNull);
      expect(speaker.said, ['Go there?']);
    });
  });

  test('a long run of words is not a command where a limit is set', () async {
    final windows = OpenWindows();
    final handled = <VoiceCommand>[];
    final c = controller(windows, Recording())..handsFree = true;
    c.attach(VoiceScope(
      commands: () => kReadingCommands,
      maxWords: () => 4,
      onCommand: (heard) async {
        handled.add(heard.command);
        return true;
      },
    ));
    await pumpEventQueue();
    await windows.hear(
        const Heard('read the instructions on the label before you use it'));
    expect(handled, isEmpty);
    await windows.hear(const Heard('next'));
    expect(handled, [VoiceCommand.next]);
    c.handsFree = false;
    await pumpEventQueue();
  });

  group('round 4', () {
    test('says once that it is listening, not on every window', () async {
      final windows = OpenWindows();
      final speaker = Recording();
      final c = controller(windows, speaker)..handsFree = true;
      c.attach(const VoiceScope());
      await pumpEventQueue();
      await windows.hear(const NotHeard(VoiceInputFailure.nothingHeard));
      c.routeChanged(Routes.settings);
      await pumpEventQueue();
      expect(speaker.said.where((s) => s == kHandsFreeListening), hasLength(1));
      c.handsFree = false;
      await pumpEventQueue();
    });

    test('an instructed phrase is heard, though the app just said it',
        () async {
      // "Say fill in" took "fill in" out of the user's own "fill in".
      final engine = HeldEngine();
      final queue = SpeechQueue(engine: engine, lineGap: Duration.zero);
      final windows = OpenWindows();
      final routes = <String>[];
      final c = controller(windows, queue, routes: routes)..handsFree = true;
      c.attach(const VoiceScope());
      await pumpEventQueue();

      unawaited(queue.speak('Say scan, read, take me to a place, or help.'));
      await pumpEventQueue();
      await windows.hear(const Heard('scan'));
      engine.finish();
      engine.finish();
      await pumpEventQueue();
      expect(routes, [Routes.scan]);
      c.handsFree = false;
      await pumpEventQueue();
    });

    test('a microphone that failed is tried again on the next screen',
        () async {
      final windows = OpenWindows();
      final c = controller(windows, Recording())..handsFree = true;
      c.routeChanged(Routes.home);
      c.attach(const VoiceScope());
      await pumpEventQueue();
      for (var i = 0; i < 5; i++) {
        await windows.hear(const NotHeard(VoiceInputFailure.failed));
      }
      expect(c.isHandsFreeActive, isFalse);

      c.routeChanged(Routes.settings);
      c.attach(const VoiceScope());
      await pumpEventQueue();
      expect(windows.open, isTrue, reason: 'given another chance');
      c.handsFree = false;
      await pumpEventQueue();
    });

    test('a refused microphone is not asked again on every screen, only on '
        'coming back to the app', () async {
      final windows =
          OpenWindows(readiness: RecognizerReadiness.microphoneBlocked);
      final speaker = Recording();
      final c = controller(windows, speaker)..handsFree = true;
      c.routeChanged(Routes.home);
      c.attach(const VoiceScope());
      await pumpEventQueue();
      c.routeChanged(Routes.settings);
      c.attach(const VoiceScope());
      await pumpEventQueue();
      expect(speaker.said.where((s) => s.contains('blocked')), hasLength(1));

      c.setForeground(false);
      c.setForeground(true);
      await pumpEventQueue();
      expect(speaker.said.where((s) => s.contains('blocked')), hasLength(2));
      c.handsFree = false;
      await pumpEventQueue();
    });
  });
}
