import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/motion/fall_detector.dart';
import 'package:impairgency/core/motion/fall_event.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/data/motion_source.dart';
import 'package:impairgency/vi/fall_watch.dart';

class _Motion implements MotionSource {
  final _controller = StreamController<MotionSample>();

  @override
  Stream<MotionSample> get samples => _controller.stream;

  void add(MotionSample sample) => _controller.add(sample);
}

class _Speaker implements PrioritySpeaker {
  final said = <(String, SpeechPriority)>[];

  @override
  String? get lastSpoken => said.isEmpty ? null : said.last.$1;

  @override
  Future<void> announce(String text, {required SpeechPriority priority}) async {
    said.add((text, priority));
  }

  @override
  Future<void> speak(String text) async =>
      announce(text, priority: SpeechPriority.info);

  @override
  Future<void> speakLines(List<String> lines) async {
    for (final line in lines) {
      await speak(line);
    }
  }

  @override
  Future<void> repeat() async {}

  @override
  Future<void> stop() async {}
}

void main() {
  final t0 = DateTime.utc(2026, 10, 20, 9);

  void trip(_Motion motion, int second) {
    final at = t0.add(Duration(seconds: second));
    motion.add(MotionSample(at: at, x: 0, y: 0, z: 40));
    for (var ms = 50; ms <= 800; ms += 50) {
      motion.add(
        MotionSample(
          at: at.add(Duration(milliseconds: ms)),
          x: 0,
          y: 0,
          z: 9.8,
        ),
      );
    }
  }

  test('asks at hazard priority, and a silence is not an answer', () async {
    final motion = _Motion();
    final speaker = _Speaker();
    var detected = 0;
    bool? result;
    final watch = FallWatch(
      motion: motion,
      speaker: speaker,
      onDetected: () => detected++,
      onFinished: ({required bool answered}) async {
        result = answered;
      },
      onCancel: () {},
      onHelp: () {},
      hear: () async => FallReply.none,
    );
    watch.start();
    trip(motion, 0);
    await pumpEventQueue();

    expect(detected, 1);
    expect(speaker.said.first, (kFallCheckPhrase, SpeechPriority.hazard));
    expect(result, isFalse);
    expect(watch.checking, isFalse);
    watch.stop();
  });

  test('okay does not ask for help, and help hands off', () async {
    final motion = _Motion();
    final speaker = _Speaker();
    final answers = <bool>[];
    var helped = 0;
    var reply = FallReply.okay;
    final watch = FallWatch(
      motion: motion,
      speaker: speaker,
      onDetected: () {},
      onFinished: ({required bool answered}) async => answers.add(answered),
      onCancel: () {},
      onHelp: () => helped++,
      hear: () async => reply,
    );
    watch.start();

    trip(motion, 0);
    await pumpEventQueue();
    expect(answers, [true]);
    expect(helped, 0);

    reply = FallReply.help;
    trip(motion, 40);
    await pumpEventQueue();
    expect(answers, [true, true]);
    expect(helped, 1);
    expect(speaker.said.last, ('Calling for help.', SpeechPriority.hazard));
    watch.stop();
  });
}
