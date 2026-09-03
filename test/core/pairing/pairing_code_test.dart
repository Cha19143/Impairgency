import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/pairing/pairing_code.dart';

void main() {
  group('the alphabet is built for being said out loud', () {
    test('excludes every character that rhymes with another', () {
      // "B", "D" and "three" are one sound over a phone line.
      for (final c in 'BCDEGPTVZ3'.split('')) {
        expect(kSpeakSafeAlphabet, isNot(contains(c)), reason: 'rhyming: $c');
      }
    });

    test('excludes characters confusable with digits', () {
      for (final c in 'ILOS015'.split('')) {
        expect(kSpeakSafeAlphabet, isNot(contains(c)), reason: 'shape: $c');
      }
    });

    test('keeps only one of the ay/jay/kay/ate family', () {
      final kept = 'AJK8'.split('').where(kSpeakSafeAlphabet.contains);
      expect(kept, isEmpty);
    });

    test('keeps M but not N', () {
      expect(kSpeakSafeAlphabet, contains('M'));
      expect(kSpeakSafeAlphabet, isNot(contains('N')));
    });

    test('has no duplicates', () {
      expect(kSpeakSafeAlphabet.split('').toSet().length,
          kSpeakSafeAlphabet.length);
    });

    test('leaves enough room that codes cannot be swept', () {
      // Any signed-in account can look a code up, so the code space is the only
      // thing between a stranger and enumeration.
      final space = pow(kSpeakSafeAlphabet.length, kPairingCodeLength);
      expect(space, greaterThan(100000000));
    });
  });

  group('generating', () {
    test('produces the right length, from the alphabet only', () {
      final rng = Random(7);
      for (var i = 0; i < 500; i++) {
        final code = generatePairingCode(random: rng);
        expect(code.length, kPairingCodeLength);
        expect(code.split('').every(kSpeakSafeAlphabet.contains), isTrue,
            reason: code);
      }
    });

    test('every generated code validates', () {
      final rng = Random(11);
      for (var i = 0; i < 500; i++) {
        expect(isValidPairingCode(generatePairingCode(random: rng)), isTrue);
      }
    });

    test('does not repeat itself in any small run', () {
      final rng = Random(3);
      final seen = {for (var i = 0; i < 500; i++) generatePairingCode(random: rng)};
      expect(seen.length, 500);
    });
  });

  group('reading a code back in', () {
    test('forgives the punctuation people add to something they heard', () {
      const code = 'FH29MR47';
      for (final typed in ['fh29 mr47', 'FH29-MR47', ' FH29MR47 ', 'fh29mr47']) {
        expect(normalisePairingCode(typed), code, reason: typed);
        expect(isValidPairingCode(typed), isTrue, reason: typed);
      }
    });

    test('does not guess at a mishearing', () {
      // "O" could plausibly mean zero, but zero is not in the alphabet either,
      // and guessing could land on a different valid code. Rejecting is safer
      // than being helpful.
      expect(isValidPairingCode('FH29MRO7'), isFalse);
      expect(isValidPairingCode('FH29MR07'), isFalse);
      expect(normalisePairingCode('FH29MRO7'), 'FH29MRO7');
    });

    test('rejects the wrong length', () {
      expect(isValidPairingCode('FH29MR4'), isFalse);
      expect(isValidPairingCode('FH29MR477'), isFalse);
      expect(isValidPairingCode(''), isFalse);
    });
  });

  group('reading a code out', () {
    test('breaks eight characters into two groups of four', () {
      expect(spokenPairingCode('FH29MR47'), 'FH29 MR47');
    });

    test('leaves a malformed code alone rather than mangling it', () {
      expect(spokenPairingCode('FH29'), 'FH29');
    });
  });

  group('rejection messages', () {
    test('each reason says something different and actionable', () {
      final messages = {
        for (final r in PairingCodeRejection.values) r: pairingRejectionMessage(r)
      };
      expect(messages.values.toSet().length, PairingCodeRejection.values.length);
      expect(messages[PairingCodeRejection.expired], contains('thirty minutes'));
      expect(messages[PairingCodeRejection.alreadyUsed], contains('new one'));
      expect(messages[PairingCodeRejection.notFound], contains('read it again'));
    });

    test('the malformed message warns about the characters that are not there',
        () {
      expect(pairingRejectionMessage(PairingCodeRejection.malformed),
          contains('letter O'));
    });
  });
}
