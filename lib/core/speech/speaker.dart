/// Text to speech, behind an interface.
///
/// Screens depend on this rather than on `flutter_tts` directly, so a widget
/// test can assert *what the app said* — which for this app is most of what
/// there is to assert.
library;

abstract interface class Speaker {
  /// The last thing said, or null if nothing has been.
  ///
  /// Backs the "repeat" command. Someone who missed a spoken warning has no
  /// way to see it again; replaying it is the only route back to information
  /// that has already gone past.
  String? get lastSpoken;

  /// Says [lastSpoken] again, or explains that there is nothing to repeat.
  Future<void> repeat();

  /// Speaks [text] as something the user asked for or needs to hear now.
  ///
  /// Replaces whatever informational speech was pending or in progress: a
  /// user who has just pressed a button does not want to hear the rest of the
  /// previous screen first. It never cuts a hazard warning short — see
  /// [PrioritySpeaker] for the rule.
  Future<void> speak(String text);

  /// Speaks each line in order, pausing between them.
  ///
  /// Separate from [speak] because the pause is what makes a multi-line notice
  /// followable by ear.
  Future<void> speakLines(List<String> lines);

  Future<void> stop();
}

/// How much one utterance matters relative to another.
///
/// Ordered least to most important, so `index` compares. There are three and
/// not more on purpose: every extra level is another decision about which of
/// two sentences a person walking into traffic hears first.
enum SpeechPriority {
  /// Screen narration, confirmations, answers to questions. Waits its turn.
  info,

  /// "Turn left", "50 metres to go". Queues behind hazards, ahead of chatter.
  navigation,

  /// "Stop, tree in front of you." The only thing that may cut another
  /// sentence off mid-word.
  hazard,
}

/// A [Speaker] that also takes priorities.
///
/// The rule, in one place so no screen can quietly change it:
///
///  * A hazard interrupts anything that is not a hazard.
///  * A hazard interrupts a *different* hazard — a new danger is new.
///  * The same hazard already being said is not said twice.
///  * Nothing else interrupts anything. Navigation and information queue in
///    priority order and each sentence finishes before the next starts.
abstract interface class PrioritySpeaker implements Speaker {
  Future<void> announce(String text, {required SpeechPriority priority});
}

/// The thing that actually makes sound. One sentence at a time.
///
/// [say] completes when the sentence has finished, or when [stop] cut it off.
/// The queue relies on that: a `say` that returned before the audio ended
/// would let the next sentence start on top of it, which is the bug the
/// queue exists to fix.
abstract interface class SpeechEngine {
  Future<void> say(String text);
  Future<void> stop();
}

/// Does nothing. Used where speech is not wanted and as a widget-test default,
/// so a screen never fails to build for want of a real engine.
class SilentSpeaker implements PrioritySpeaker {
  const SilentSpeaker();

  @override
  String? get lastSpoken => null;

  @override
  Future<void> repeat() async {}

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> speakLines(List<String> lines) async {}

  @override
  Future<void> announce(String text,
      {required SpeechPriority priority}) async {}

  @override
  Future<void> stop() async {}
}

/// Gives any [Speaker] the priority interface, without the priority.
///
/// For tests and fakes that only record what was said. Everything goes
/// through [Speaker.speak], so the recording is complete; the ordering rule is
/// tested against the real queue.
class FlatPrioritySpeaker implements PrioritySpeaker {
  const FlatPrioritySpeaker(this.inner);

  final Speaker inner;

  @override
  String? get lastSpoken => inner.lastSpoken;

  @override
  Future<void> repeat() => inner.repeat();

  @override
  Future<void> speak(String text) => inner.speak(text);

  @override
  Future<void> speakLines(List<String> lines) => inner.speakLines(lines);

  @override
  Future<void> announce(String text, {required SpeechPriority priority}) =>
      inner.speak(text);

  @override
  Future<void> stop() => inner.stop();
}

/// Lifts a plain [Speaker] to a [PrioritySpeaker], keeping it if it already
/// is one.
PrioritySpeaker withPriorities(Speaker speaker) =>
    speaker is PrioritySpeaker ? speaker : FlatPrioritySpeaker(speaker);

/// What the app says when there is nothing to say again.
const String kNothingToRepeat = 'There is nothing to repeat yet.';
