/// How fast the app talks.
///
/// Normal is the rate the speech engine already uses, 0.45. Choosing a pace
/// never changes that default; it only applies a rate the user picked.
enum SpeechPace { slow, normal, fast }

extension SpeechPaceValue on SpeechPace {
  /// Platform speech rate. [normal] stays 0.45.
  double get rate => switch (this) {
        SpeechPace.slow => 0.35,
        SpeechPace.normal => 0.45,
        SpeechPace.fast => 0.6,
      };

  String get label => switch (this) {
        SpeechPace.slow => 'Slow',
        SpeechPace.normal => 'Normal',
        SpeechPace.fast => 'Fast',
      };

  SpeechPace get next => switch (this) {
        SpeechPace.slow => SpeechPace.normal,
        SpeechPace.normal => SpeechPace.fast,
        SpeechPace.fast => SpeechPace.slow,
      };

  static SpeechPace? parse(String? raw) {
    for (final pace in SpeechPace.values) {
      if (pace.name == raw) return pace;
    }
    return null;
  }
}
