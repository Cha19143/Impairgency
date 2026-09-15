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

  test('help inside the app sentence is removed, help alone is kept', () {
    expect(withoutEcho('calling for help in 3', [armingAnnouncement(3)]), '');
    expect(withoutEcho('help', countdown), 'help');
  });
}
