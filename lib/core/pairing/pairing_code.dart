/// Invitation codes, designed to be *said out loud*.
///
/// A visually impaired user reads this code to their guardian, often over the
/// phone. That single fact drives every decision here, and it is why the
/// alphabet is not the usual Base32.
library;

import 'dart:math';

/// Characters chosen so no two are confusable when spoken in English.
///
/// Excluded, and why:
///
/// * **B C D E G P T V Z, and 3** — they all rhyme. Over a phone line "B" and
///   "D" and "three" are the same sound.
/// * **I, L, O, S, and 0, 1, 5** — confusable with each other by shape when
///   typed and by sound when said.
/// * **A, J, K, and 8** — "ay", "jay", "kay", "ate" are one vowel apart.
/// * **N** — kept M, dropped N; "em" and "en" are the classic mishearing.
/// * **U, W, Q** — "you" is an English word, "double-you" is three syllables,
///   "cue" collides with the letter Q spoken as a word.
///
/// What survives is phonetically distinct end to end: two, four, six, seven,
/// nine, eff, aitch, em, ar, ex, why.
const String kSpeakSafeAlphabet = '24679FHMRXY';

/// Eight characters, read as two groups of four.
///
/// Longer than the usual six on purpose. Any signed-in account can look up a
/// code — a guardian has to be able to, before any link exists — so the code
/// space is the only thing standing between a stranger and an enumeration
/// attack. Eleven characters to the eighth is about 214 million; six would be
/// under three million, which a script could sweep while a code was still live.
///
/// The real hardening is to move redemption behind a Cloud Function that can
/// rate-limit. Until then, length is what there is.
const int kPairingCodeLength = 8;

/// Long enough to read aloud and type; short enough that a code overheard in a
/// waiting room is useless by the time anyone acts on it.
const Duration kPairingCodeLifetime = Duration(minutes: 30);

/// A new code. Pass a seeded [Random] in tests; the default is cryptographic.
String generatePairingCode({Random? random}) {
  final rng = random ?? Random.secure();
  return List.generate(
    kPairingCodeLength,
    (_) => kSpeakSafeAlphabet[rng.nextInt(kSpeakSafeAlphabet.length)],
  ).join();
}

/// Strips the punctuation people add when they write down something they heard.
///
/// Deliberately does *not* map near-misses back — "O" does not become "0".
/// Guessing at a mishearing could land on a different valid code, which is a
/// worse failure than telling someone the code was wrong.
String normalisePairingCode(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

bool isValidPairingCode(String input) {
  final code = normalisePairingCode(input);
  return code.length == kPairingCodeLength &&
      code.split('').every(kSpeakSafeAlphabet.contains);
}

/// The code split for reading aloud: `FH29 MR47` rather than `FH29MR47`.
///
/// An unbroken run of eight is hard to hold in your head; two groups of four
/// is how people already say phone numbers.
String spokenPairingCode(String code) {
  final clean = normalisePairingCode(code);
  if (clean.length != kPairingCodeLength) return clean;
  return '${clean.substring(0, 4)} ${clean.substring(4)}';
}

/// Why a code could not be redeemed. Each needs a different thing said.
enum PairingCodeRejection { malformed, notFound, alreadyUsed, expired }

String pairingRejectionMessage(PairingCodeRejection reason) =>
    switch (reason) {
      PairingCodeRejection.malformed =>
        'That is not a valid code. It is eight characters, and it does not '
            'contain the letter O or the number zero.',
      PairingCodeRejection.notFound =>
        'We could not find that code. Ask them to read it again.',
      PairingCodeRejection.alreadyUsed =>
        'That code has already been used. Ask them to create a new one.',
      PairingCodeRejection.expired =>
        'That code has expired. Codes last thirty minutes. Ask them to create '
            'a new one.',
    };
