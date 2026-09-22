import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/sos/sos_countdown.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/core/voice/voice_commands.dart';
import 'package:impairgency/vi/cancel_listener.dart';

import 'voice_fakes.dart';

/// A pause that lets the rest of the test run, however short.
Future<void> soon(Duration _) => Future<void>.delayed(Duration.zero);

void main() {
  final countdown = [
    for (var s = 3; s >= 0; s--) armingAnnouncement(s, contactName: 'Mum'),
    ...kArmingHintLines,
  ];

  test('a window that heard only the app is opened again', () async {
    // The one window the countdown had heard itself, took that out, and
    // closed with seconds to go. Nothing opened another.
    final mic = OpenWindows();
    final c = voiceControllerFor(mic, Recording());
    final heard = <VoiceCommand>[];
    c.commands.listen(heard.add);
    final listener = CancelListener(c, echoOf: () => countdown, wait: soon);

    final running = listener.run();
    await pumpEventQueue();
    expect(mic.sessions, hasLength(1));

    await mic.hear(const Heard('calling mum in 3 say cancel or touch the '
        'screen anywhere'));
    expect(mic.sessions, hasLength(2));
    expect(mic.open, isTrue, reason: 'still listening');

    await mic.hear(const Heard('cancel'));
    expect(heard, [VoiceCommand.cancel]);

    await listener.stop();
    await running;
    expect(mic.open, isFalse);
  });

  test('a move to another screen ends it', () async {
    final mic = OpenWindows();
    final c = voiceControllerFor(mic, Recording())..routeChanged('/sos');
    final listener = CancelListener(c, echoOf: () => countdown, wait: soon);

    final running = listener.run();
    await pumpEventQueue();
    expect(mic.sessions, hasLength(1));

    c.routeChanged('/home');
    await running;
    await pumpEventQueue();
    expect(mic.sessions, hasLength(1), reason: 'not reopened on /home');
  });

  test('a window someone else opened is left to them', () async {
    // Taking it straight back would leave two things fighting over one
    // microphone, each closing the other's window.
    final mic = OpenWindows();
    final c = voiceControllerFor(mic, Recording());
    final listener = CancelListener(c, echoOf: () => countdown, wait: soon);
    final running = listener.run();
    await pumpEventQueue();

    final other = c.listen(preempt: true);
    await pumpEventQueue();
    expect(mic.open, isTrue);

    await pumpEventQueue();
    expect(mic.sessions, hasLength(2), reason: 'not taken back');

    await listener.stop();
    await running;
    expect(mic.open, isTrue,
        reason: "the other listening is not the listener's");

    await c.stop();
    await other;
  });

  test('nothing is reopened while the app is behind another', () async {
    final mic = OpenWindows();
    final c = voiceControllerFor(mic, Recording());
    final listener = CancelListener(c, echoOf: () => countdown, wait: soon);
    final running = listener.run();
    await pumpEventQueue();

    c.setForeground(false);
    await pumpEventQueue();
    expect(mic.sessions, hasLength(1));
    expect(mic.open, isFalse);

    c.setForeground(true);
    await pumpEventQueue();
    expect(mic.sessions, hasLength(2), reason: 'back on screen, listening');

    await listener.stop();
    await running;
  });

  test('a blocked microphone is not asked again and again', () async {
    final mic = OpenWindows(readiness: RecognizerReadiness.microphoneBlocked);
    final c = voiceControllerFor(mic, Recording());
    final listener = CancelListener(c, echoOf: () => countdown, wait: soon);

    await listener.run();
    expect(mic.sessions, isEmpty);
    expect(listener.isRunning, isFalse);
  });
}
