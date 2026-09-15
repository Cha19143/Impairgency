import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/listening_policy.dart';

void main() {
  test('after a phrase, silence or chatter, the microphone reopens at once', () {
    for (final outcome in [
      ListenOutcome.acted,
      ListenOutcome.nothingHeard,
      ListenOutcome.notUnderstood,
      ListenOutcome.cancelled,
    ]) {
      expect(delayBeforeListening(outcome),
          lessThanOrEqualTo(const Duration(milliseconds: 250)),
          reason: '$outcome');
    }
  });

  test('a blocked microphone is not asked again', () {
    expect(delayBeforeListening(ListenOutcome.blocked), isNull);
  });

  test('no connection backs off, and keeps trying', () {
    expect(delayBeforeListening(ListenOutcome.network),
        const Duration(seconds: 5));
    expect(delayBeforeListening(ListenOutcome.network, failuresInARow: 2),
        const Duration(seconds: 20));
    expect(delayBeforeListening(ListenOutcome.network, failuresInARow: 99),
        const Duration(seconds: 60));
  });

  test('a failing microphone backs off, then gives up after four', () {
    expect(delayBeforeListening(ListenOutcome.failed),
        const Duration(seconds: 1));
    expect(delayBeforeListening(ListenOutcome.failed, failuresInARow: 3),
        const Duration(seconds: 8));
    expect(delayBeforeListening(ListenOutcome.failed, failuresInARow: 4),
        isNull);
  });

  test('the sentence for giving up says the buttons still work', () {
    expect(kHandsFreeStopped, contains('Tap to speak still works'));
  });
}
