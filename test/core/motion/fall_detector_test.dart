import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/alerts/guardian_alert.dart';
import 'package:impairgency/core/motion/fall_detector.dart';
import 'package:impairgency/core/motion/fall_event.dart';
import 'package:impairgency/core/voice/voice_commands.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 20, 9);

  MotionSample sample(int ms, double z) =>
      MotionSample(at: t0.add(Duration(milliseconds: ms)), x: 0, y: 0, z: z);

  test('walking, a gentle put-down, and a bump do not fire', () {
    final detector = FallDetector();
    var fired = false;
    for (var ms = 0; ms < 3000; ms += 50) {
      final walking = (ms ~/ 50).isEven ? 8.0 : 16.0;
      fired = detector.note(sample(ms, walking)) || fired;
    }
    expect(fired, isFalse);

    final gentle = FallDetector();
    expect(gentle.note(sample(0, 18)), isFalse);
    for (var ms = 50; ms <= 1000; ms += 50) {
      expect(gentle.note(sample(ms, 9.8)), isFalse);
    }

    final bump = FallDetector();
    expect(bump.note(sample(0, 40)), isFalse);
    var bumpFired = false;
    for (var ms = 50; ms <= 2000; ms += 50) {
      bumpFired = bump.note(sample(ms, 18)) || bumpFired;
    }
    expect(bumpFired, isFalse);
  });

  test('a spike followed by stillness fires once, then waits out the cooldown', () {
    final detector = FallDetector();
    expect(detector.note(sample(0, 40)), isFalse);
    var firedAt = -1;
    for (var ms = 50; ms <= 800; ms += 50) {
      if (detector.note(sample(ms, 9.8))) firedAt = ms;
    }
    expect(firedAt, greaterThanOrEqualTo(700));

    expect(detector.note(sample(2000, 40)), isFalse);
    var again = false;
    for (var ms = 2050; ms <= 2800; ms += 50) {
      again = detector.note(sample(ms, 9.8)) || again;
    }
    expect(again, isFalse);

    expect(detector.note(sample(40000, 40)), isFalse);
    var later = false;
    for (var ms = 40050; ms <= 40800; ms += 50) {
      later = detector.note(sample(ms, 9.8)) || later;
    }
    expect(later, isTrue);
  });

  test('lowering the impact threshold is what lets a hard shake count', () {
    final sensitive = FallDetector(impactThreshold: 15);
    expect(sensitive.note(sample(0, 18)), isFalse);
    var fired = false;
    for (var ms = 50; ms <= 800; ms += 50) {
      fired = sensitive.note(sample(ms, 9.8)) || fired;
    }
    expect(fired, isTrue);
  });

  test('okay, oo, and I am okay cancel; help does not', () {
    FallReply reply(String words) =>
        fallReplyFrom(parseVoiceCommand(words, only: kFallReplyCommands)?.command);

    expect(reply('oo'), FallReply.okay);
    expect(reply('okay'), FallReply.okay);
    expect(reply('okay lang ako'), FallReply.okay);
    expect(reply("I'm okay"), FallReply.okay);
    expect(reply('yes'), FallReply.okay);
    expect(reply('tulong'), FallReply.help);
    expect(reply('help'), FallReply.help);
    expect(reply('the bus is loud'), FallReply.none);
  });

  test('the guardian sentence names the person', () {
    final alert = GuardianAlert(
      id: 'f',
      userId: 'u',
      kind: kGuardianAlertFall,
      message: kFallAlertMessage,
      at: t0,
    );
    expect(
      guardianAlertSentence(alert, 'Ana'),
      'Ana may have fallen and did not respond',
    );
  });
}
