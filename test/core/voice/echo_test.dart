import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/sos/sos_countdown.dart';
import 'package:impairgency/core/voice/echo.dart';
import 'package:impairgency/core/voice/voice_commands.dart';

void main() {
  final countdown = [
    for (var s = 5; s >= 0; s--) armingAnnouncement(s, contactName: 'Mum'),
    ...kArmingHintLines,
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

  group('what the app tells the user to say', () {
    // "Say fill in" took "fill in" out of the user's own "fill in", because
    // the app had just said it. Hands-free heard nothing; only a tap worked.
    test('are the phrases after say', () {
      expect(instructedPhrases('Say Create account when you are ready.'),
          ['create account']);
      expect(instructedPhrases('Say scan, read, take me to a place, or help.'),
          ['scan', 'read', 'take me', 'help']);
      expect(
          instructedPhrases('If you are all right now, say: I am okay. Your '
              'guardian will be told.'),
          ['i am okay']);
      expect(instructedPhrases('Or say fill in, to answer by voice.'),
          ['fill in']);
    });

    test('do not run on past the end of the sentence', () {
      expect(instructedPhrases('Say help. Then wait.'), ['help']);
      expect(instructedPhrases('Say cancel, and your guardian will be told.'),
          ['cancel']);
    });

    test('a sentence with no say has none', () {
      expect(instructedPhrases('Or touch the screen anywhere.'), isEmpty);
      expect(instructedPhrases(kCancelledAnnouncement), isEmpty);
    });

    test('said by the user, they are kept', () {
      expect(withoutEcho('fill in', ['Say fill in to answer by voice.']),
          'fill in');
      expect(
          withoutEcho('create account',
              ['Say Create account when you are ready.']),
          'create account');
      expect(
          withoutEcho('take me home',
              ['Say scan, read, take me to a place, or help.']),
          'take me home');
      expect(
          withoutEcho('i am okay',
              ['If you are all right now, say: I am okay. Your guardian will '
                  'be told.']),
          'i am okay');
    });

    test("the app's own sentence heard back is still taken out", () {
      expect(
          withoutEcho('say create account when you are ready',
              ['Say Create account when you are ready.']),
          '');
      expect(
          withoutEcho('say scan read take me to a place or help',
              ['Say scan, read, take me to a place, or help.']),
          '');
      expect(
          withoutEcho('say i am okay your guardian will be told',
              ['If you are all right now, say: I am okay. Your guardian will '
                  'be told.']),
          '');
      expect(withoutEcho('say cancel', kArmingHintLines), '');
    });
  });
}
