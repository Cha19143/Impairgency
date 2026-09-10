/// Hearing a command, behind an interface.
///
/// Flutter-free, like the rest of `core/`, so the controller that decides
/// what to do with a failure can be tested without a microphone. The real
/// recogniser lives in `lib/data/stt_speech_recognizer.dart`.
///
/// This file exists because the previous release had none of it: the
/// vocabulary and its parser were ported and tested, the dashboard said "Say
/// scan, navigate, or help", and nothing anywhere opened the microphone. The
/// tester who reported that voice commands "do not work at all" was right,
/// and it was not their device.
library;

/// Whether the recogniser can be started at all, and if not, why not.
///
/// Four answers rather than a bool because three of them need three
/// different things said, and one of them — [microphoneBlocked] — needs the
/// app to stop asking.
enum RecognizerReadiness {
  ready,

  /// Not granted. Asking again is allowed; the user may have dismissed the
  /// prompt by accident, or refused it once.
  microphoneDenied,

  /// Refused permanently, or restricted by policy. Only Settings can change
  /// it, so that is what the app has to say.
  microphoneBlocked,

  /// No speech recognition service on this device: an emulator, a phone
  /// without a Google app, a stripped-down build.
  unavailable,
}

/// What went wrong with one attempt to hear something.
enum VoiceInputFailure {
  microphoneDenied,
  microphoneBlocked,
  unavailable,

  /// The recogniser needs a connection and there is none.
  network,

  /// The listening window closed with no speech at all.
  nothingHeard,

  /// Words were heard, and none of them is a command.
  notUnderstood,

  /// Anything else: the recogniser was busy, the audio pipeline failed.
  failed,
}

/// The outcome of one listening window.
sealed class VoiceHearing {
  const VoiceHearing();
}

class Heard extends VoiceHearing {
  const Heard(this.words);

  final String words;
}

class NotHeard extends VoiceHearing {
  const NotHeard(this.failure);

  final VoiceInputFailure failure;
}

abstract interface class SpeechRecognizer {
  /// Checks permission and the service, prompting for permission if that is
  /// still allowed. Cheap to call again once it has answered [ready].
  Future<RecognizerReadiness> prepare();

  /// Listens for one phrase.
  ///
  /// Completes when the phrase ends, when the window closes, or when the
  /// attempt fails. Never throws for the ordinary failures — a microphone
  /// that could not be opened is a [NotHeard], not an exception.
  Future<VoiceHearing> listen({
    Duration listenFor = kListenWindow,
    Duration pauseFor = kPauseEndsPhrase,
    void Function(String partial)? onPartial,
  });

  /// Stops listening without waiting for a result.
  Future<void> cancel();
}

/// How long the microphone stays open waiting for a command.
const Duration kListenWindow = Duration(seconds: 8);

/// Silence that ends a phrase.
const Duration kPauseEndsPhrase = Duration(seconds: 2);

VoiceInputFailure failureForReadiness(RecognizerReadiness readiness) =>
    switch (readiness) {
      RecognizerReadiness.ready => VoiceInputFailure.failed,
      RecognizerReadiness.microphoneDenied =>
        VoiceInputFailure.microphoneDenied,
      RecognizerReadiness.microphoneBlocked =>
        VoiceInputFailure.microphoneBlocked,
      RecognizerReadiness.unavailable => VoiceInputFailure.unavailable,
    };

/// What the app says when it could not hear a command.
///
/// Every sentence ends by saying that the buttons still work. Voice is the
/// convenient way in, not the only one, and a user who has just been told the
/// microphone is blocked should not be left wondering whether the app is.
String voiceFailureMessage(
  VoiceInputFailure failure, {
  String? transcript,
  List<String> examples = const ['scan', 'navigate', 'help', 'repeat'],
}) {
  final tryThese = examples.isEmpty
      ? ''
      : ' You can say ${_joinOr(examples)}.';
  return switch (failure) {
    VoiceInputFailure.microphoneDenied =>
      'The microphone is off for this app, so voice commands cannot work. '
          'Allow the microphone when asked. The buttons still work.',
    VoiceInputFailure.microphoneBlocked =>
      'The microphone is blocked for ImpairGency. To use voice commands, open '
          'Settings, find ImpairGency, and allow the microphone. The buttons '
          'still work.',
    VoiceInputFailure.unavailable =>
      'Speech recognition is not available on this phone, so voice commands '
          'cannot work. The buttons still work.',
    VoiceInputFailure.network =>
      'Voice commands need a connection on this phone, and there is none '
          'right now. The buttons still work.',
    VoiceInputFailure.nothingHeard =>
      'I did not hear anything.$tryThese',
    VoiceInputFailure.notUnderstood => transcript == null || transcript.isEmpty
        ? 'I did not catch a command.$tryThese'
        : 'I heard "$transcript", but that is not a command.$tryThese',
    VoiceInputFailure.failed =>
      'Voice commands are not working right now. The buttons still work.',
  };
}

String _joinOr(List<String> words) {
  if (words.length == 1) return words.single;
  return '${words.sublist(0, words.length - 1).join(', ')}, or ${words.last}';
}
