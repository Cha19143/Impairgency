import 'dart:async';

import '../core/motion/fall_detector.dart';
import '../core/motion/fall_event.dart';
import '../core/speech/speaker.dart';
import '../core/speech/speech_queue.dart';
import '../core/voice/listening_policy.dart';
import '../data/motion_source.dart';
import 'voice_controller.dart';

/// Listens for a fall while Scan or a journey is open, asks if the person
/// is all right, and reports the answer.
///
/// Stop it when the screen closes. It does not run anywhere else.
class FallWatch {
  FallWatch({
    required this.motion,
    required this.speaker,
    required this.onDetected,
    required this.onFinished,
    required this.onCancel,
    required this.onHelp,
    this.voice,
    this.hear,
    FallDetector? detector,
  }) : _detector = detector ?? FallDetector();

  final MotionSource motion;
  final PrioritySpeaker speaker;
  final VoiceController? voice;

  /// Replaces the microphone in a test. The phone uses [voice].
  final Future<FallReply> Function()? hear;
  final void Function() onDetected;
  final Future<void> Function({required bool answered}) onFinished;
  final void Function() onCancel;
  final void Function() onHelp;
  final FallDetector _detector;

  StreamSubscription<MotionSample>? _sub;
  var _generation = 0;

  /// True from the spike until the answer, so obstacle warnings wait.
  bool checking = false;

  void start() {
    _sub ??= motion.samples.listen(_onSample, onError: (_) {});
  }

  void stop() {
    _generation++;
    checking = false;
    _holdRoutine(false);
    _sub?.cancel();
    _sub = null;
  }

  void _onSample(MotionSample sample) {
    if (checking) return;
    if (!_detector.note(sample)) return;
    final generation = _generation;
    checking = true;
    _holdRoutine(true);
    unawaited(_check(generation));
  }

  Future<void> _check(int generation) async {
    var pending = false;
    try {
      onDetected();
      pending = true;
      await speaker.announce(kFallCheckPhrase, priority: SpeechPriority.hazard);
      if (generation != _generation) return;
      final reply = await (hear ?? _hear)();
      if (generation != _generation) return;
      pending = false;
      if (reply == FallReply.abandoned) {
        onCancel();
        return;
      }
      if (reply == FallReply.help) {
        await onFinished(answered: true);
        if (generation != _generation) return;
        await speaker.announce(
          'Calling for help.',
          priority: SpeechPriority.hazard,
        );
        onHelp();
        return;
      }
      await onFinished(answered: reply == FallReply.okay);
    } finally {
      if (generation != _generation && pending) onCancel();
      if (generation == _generation) {
        checking = false;
        _holdRoutine(false);
      }
    }
  }

  Future<FallReply> _hear() async {
    final voice = this.voice;
    if (voice == null) {
      await Future<void>.delayed(kFallResponseTimeout);
      return FallReply.none;
    }
    final outcome = await voice.listen(
      only: kFallReplyCommands,
      dispatch: false,
      preempt: true,
      quiet: true,
      silenceSpeaker: true,
      listenFor: kFallResponseTimeout,
      echoOf: () => const [kFallCheckPhrase],
    );
    if (outcome == ListenOutcome.cancelled) return FallReply.abandoned;
    if (outcome != ListenOutcome.acted) return FallReply.none;
    return fallReplyFrom(voice.lastCommand);
  }

  /// Directions wait. A hazard, including the question itself, does not.
  void _holdRoutine(bool hold) {
    final queue = speaker;
    if (queue is SpeechQueue) queue.holdRoutineSpeech = hold;
  }
}
