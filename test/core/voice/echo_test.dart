import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/sos/sos_countdown.dart';
import 'package:impairgency/core/voice/echo.dart';
import 'package:impairgency/core/voice/voice_commands.dart';

void main() {
  final countdown = [
    for (var s = 5; s >= 0; s--) armingAnnouncement(s, contactName: 'Mum'),
    kArmingHint,
  ];

  VoiceCommand? heardDuringCountdown(String transcript) => matchVoiceCommand(
      withoutEcho(transcript, countdown),
      only: kCancellationCommands);

  test("the countdown's own sentence does not cancel it", () {
    // What the microphone hears while the countdown talks. It says the word
    // "cancel", and a recogniser that hears the sentence hears the word.
    expect(heardDuringCountdown(kArmingHint), isNull);
    expect(heardDuringCountdown('say cancel or touch the screen'), isNull);
    expect(heardDuringCountdown('calling mum in 3 say cancel'), isNull);
    expect(heardDuringCountdown('calling mum in three'), isNull,
        reason: 'digits and number words are the same word');
  });

  test('the user saying cancel over the top of it still cancels', () {
    expect(heardDuringCountdown('cancel'), VoiceCommand.cancel);
    expect(heardDuringCountdown('touch the screen anywhere cancel'),
        VoiceCommand.cancel);
    expect(heardDuringCountdown('stop'), VoiceCommand.cancel);
  });

  test('a single word is never treated as the app', () {
    expect(withoutEcho('cancel', ['Say cancel, or touch the screen.']),
        'cancel');
  });

  test("a one-word sentence of the app's, heard back whole, is the app", () {
    // A button pressed by voice is named as it is pressed. Heard back by the
    // next window, "Continue" would press Continue on the next screen too.
    expect(withoutEcho('continue', ['Continue.']), '');
    expect(withoutEcho('continue please', ['Continue.']), 'continue please');
    expect(withoutEcho('cancel', ['Cancel.', kArmingHint]), '');
  });

  test('help inside the app sentence is removed, help alone is kept', () {
    expect(withoutEcho('calling for help in 3', [armingAnnouncement(3)]), '');
    expect(withoutEcho('help', countdown), 'help');
  });

  group('a partial result that may still become the app', () {
    const hint = 'Say cancel, or touch the screen anywhere, to stop this.';

    test('ends in a word the app says with more to come', () {
      // The microphone can open after "say": the next partial may be
      // "cancel or touch", the app's own sentence.
      expect(mayBeEchoStart('cancel', [hint]), isTrue);
      expect(mayBeEchoStart('calling mum in 3 cancel', [hint]), isTrue);
    });

    test('a word the app does not say can be acted on at once', () {
      expect(mayBeEchoStart('teka', [hint]), isFalse);
      expect(mayBeEchoStart('cancel it', [hint]), isFalse);
    });

    test("the last word of the app's sentence has nothing to come", () {
      expect(mayBeEchoStart('this', [hint]), isFalse);
    });

    test('nothing heard, or nothing said, is nothing to wait for', () {
      expect(mayBeEchoStart('', [hint]), isFalse);
      expect(mayBeEchoStart('cancel', const []), isFalse);
    });
  });
}
