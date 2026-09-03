/// Text to speech, behind an interface.
///
/// Screens depend on this rather than on `flutter_tts` directly, so a widget
/// test can assert *what the app said* — which for this app is most of what
/// there is to assert.
library;

abstract interface class Speaker {
  /// Speaks [text], interrupting anything already in progress.
  Future<void> speak(String text);

  /// Speaks each line in order, pausing between them.
  ///
  /// Separate from [speak] because the pause is what makes a multi-line notice
  /// followable by ear.
  Future<void> speakLines(List<String> lines);

  Future<void> stop();
}

/// Does nothing. Used where speech is not wanted and as a widget-test default,
/// so a screen never fails to build for want of a real engine.
class SilentSpeaker implements Speaker {
  const SilentSpeaker();

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> speakLines(List<String> lines) async {}

  @override
  Future<void> stop() async {}
}
