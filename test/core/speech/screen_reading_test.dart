import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/speech/screen_reading.dart';
import 'package:impairgency/core/speech/speech_pace.dart';

void main() {
  test('drops blanks and lines already said', () {
    expect(
      screenReadingLines([
        'Say scan, read, take me to a place, or help.',
        '  ',
        'SCAN ENVIRONMENT',
        'Read',
        'READ TEXT',
        'Say scan, read, take me to a place, or help.',
        null,
      ]),
      [
        'Say scan, read, take me to a place, or help.',
        'SCAN ENVIRONMENT',
        'READ TEXT',
      ],
    );
  });

  test('normal stays the rate the engine already uses', () {
    expect(SpeechPace.normal.rate, 0.45);
    expect(SpeechPace.slow.rate, lessThan(0.45));
    expect(SpeechPace.fast.rate, greaterThan(0.45));
    expect(SpeechPace.normal.next, SpeechPace.fast);
    expect(SpeechPace.fast.next, SpeechPace.slow);
    expect(SpeechPaceValue.parse('normal'), SpeechPace.normal);
    expect(SpeechPaceValue.parse('nope'), isNull);
  });
}
