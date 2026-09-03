/// The limitation notice the requirements document asks for.
///
/// §7: *"AI guidance should assist users but should not guarantee that an
/// environment is completely safe."*
///
/// Kept here, free of Flutter, for two reasons. It is the one piece of copy in
/// the app with a legal and ethical weight behind it, so it should be reviewable
/// in one place rather than embedded in a widget tree. And a test can assert
/// properties of it — that it is spoken in short lines, that it names concrete
/// failures rather than hedging — which is not something a `Text` widget allows.
library;

class SafetyNotice {
  const SafetyNotice({required this.headline, required this.lines});

  final String headline;

  /// Spoken and rendered one at a time. Short lines on purpose: a screen reader
  /// user who misses a long sentence has to replay the whole thing.
  final List<String> lines;

  /// The whole notice as one string, for a screen reader summary.
  String get spoken => '$headline. ${lines.join(' ')}';
}

/// The notice itself.
///
/// It names specific things the app gets wrong. A notice that says only
/// "results may vary" tells a blind user nothing they can act on; "it can miss a
/// step" tells them to keep the cane down.
const SafetyNotice kSafetyNotice = SafetyNotice(
  headline: 'What this app can and cannot do',
  lines: [
    'ImpairGency helps you notice what is around you.',
    'It will not always be right. It can miss a step, a low branch, '
        'or a car that is moving.',
    'Keep using your cane, your dog, and your own judgement. '
        'This is one more help, not a replacement for them.',
    'You can hear this again at any time from the main screen.',
  ],
);
