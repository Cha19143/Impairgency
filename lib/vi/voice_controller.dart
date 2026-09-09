import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/speech/speaker.dart';
import '../core/voice/speech_recognizer.dart';
import '../core/voice/voice_commands.dart';
import 'voice_actions.dart';

/// Where one attempt to hear a command is, for the screen to show.
enum VoicePhase {
  idle,

  /// Checking permission and the service.
  preparing,

  /// The microphone is open.
  listening,

  /// A command was recognised and is being acted on.
  heard,

  /// Nothing usable was heard. [VoiceController.failureMessage] says why.
  failed,
}

/// The one path from a microphone to something happening.
///
/// permission → capture → recognition → [matchVoiceCommand] → [VoiceActions].
/// Every break in that chain ends in [VoicePhase.failed] with a sentence that
/// is both shown and spoken, because a voice feature that fails silently is
/// indistinguishable from one that does not exist — which is exactly what the
/// tester reported.
///
/// Screens that can act on a command themselves — the SOS countdown, which
/// listens for "cancel" — read [commands] instead of letting this dispatch.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.recognizer,
    required this.speaker,
    required this.actions,
    this.onNavigate,
  });

  final SpeechRecognizer recognizer;
  final Speaker speaker;

  /// Built fresh for each command, so it sees the current contact, guardian
  /// and device state rather than the ones at construction.
  final VoiceActions Function() actions;

  /// Where to go when a command has somewhere to go. Set by the router.
  void Function(String route)? onNavigate;

  VoicePhase _phase = VoicePhase.idle;
  String? _transcript;
  String? _failureMessage;
  VoiceCommand? _lastCommand;
  int _attempt = 0;

  VoicePhase get phase => _phase;

  /// What was heard, partial or final.
  String? get transcript => _transcript;

  /// Why the last attempt failed, in the words that were spoken.
  String? get failureMessage => _failureMessage;

  VoiceCommand? get lastCommand => _lastCommand;

  final _commands = StreamController<VoiceCommand>.broadcast();

  /// Every recognised command, whether or not it was dispatched.
  Stream<VoiceCommand> get commands => _commands.stream;

  bool get isBusy =>
      _phase == VoicePhase.preparing || _phase == VoicePhase.listening;

  bool _explainedOnce = false;

  /// Listens for one phrase and acts on it.
  ///
  /// [only] restricts the vocabulary to what the current screen can do.
  /// [dispatch] false means the caller will act on [commands] itself.
  /// [auto] is for listening the app started itself, after a prompt such as
  /// "Say scan, navigate, or help": hearing nothing is then not worth
  /// interrupting the user about, and a microphone that cannot work is
  /// explained out loud once, not on every screen. A tap on the button is
  /// never quiet.
  /// [silenceSpeaker] stops the app talking so the microphone hears the
  /// user. The SOS countdown keeps talking — it is counting down — and
  /// passes false.
  Future<void> listen({
    Set<VoiceCommand>? only,
    bool dispatch = true,
    bool auto = false,
    bool silenceSpeaker = true,
  }) async {
    if (isBusy) return;
    final attempt = ++_attempt;
    _set(VoicePhase.preparing, transcript: null, failure: null);

    final readiness = await recognizer.prepare();
    if (attempt != _attempt) return;
    if (readiness != RecognizerReadiness.ready) {
      final explain = !auto || !_explainedOnce;
      _explainedOnce = true;
      await _fail(failureForReadiness(readiness), only: only, spoken: explain);
      return;
    }

    // The microphone would otherwise hear the app talking. A hazard warning
    // is not narration and is left alone; see SpeechQueue.
    if (silenceSpeaker) await speaker.stop();
    _set(VoicePhase.listening);

    final hearing = await recognizer.listen(
      onPartial: (partial) {
        if (attempt != _attempt) return;
        _transcript = partial;
        notifyListeners();
      },
    );
    if (attempt != _attempt) return;

    switch (hearing) {
      case NotHeard(:final failure):
        if (failure == VoiceInputFailure.nothingHeard && auto) {
          _set(VoicePhase.idle);
          return;
        }
        await _fail(failure, only: only);
      case Heard(:final words):
        _transcript = words;
        final command = matchVoiceCommand(words, only: only);
        if (command == null) {
          await _fail(VoiceInputFailure.notUnderstood,
              only: only, transcript: words);
          return;
        }
        _lastCommand = command;
        _set(VoicePhase.heard);
        _commands.add(command);
        if (dispatch) await _dispatch(command);
        if (attempt == _attempt && _phase == VoicePhase.heard) {
          _set(VoicePhase.idle);
        }
    }
  }

  Future<void> _dispatch(VoiceCommand command) async {
    final outcome = await actions().handle(command);
    if (outcome.repeatLast) {
      await speaker.repeat();
    } else {
      await speaker.speak(outcome.spoken);
    }
    final route = outcome.route;
    if (route != null) onNavigate?.call(route);
  }

  Future<void> _fail(
    VoiceInputFailure failure, {
    Set<VoiceCommand>? only,
    String? transcript,
    bool spoken = true,
  }) async {
    final message = voiceFailureMessage(
      failure,
      transcript: transcript,
      examples: examplesFor(only ?? kEverydayCommands),
    );
    _set(VoicePhase.failed, failure: message);
    // Said as well as shown. The person this app is for cannot see the
    // status line.
    if (spoken) await speaker.speak(message);
  }

  /// Stops listening. The attempt in progress is abandoned, not acted on.
  Future<void> stop() async {
    _attempt++;
    await recognizer.cancel();
    _set(VoicePhase.idle);
  }

  bool _disposed = false;

  void _set(VoicePhase phase, {String? transcript, String? failure}) {
    if (_disposed) return;
    _phase = phase;
    if (phase == VoicePhase.preparing) {
      _transcript = transcript;
      _failureMessage = failure;
    } else if (failure != null) {
      _failureMessage = failure;
    }
    notifyListeners();
  }

  /// The first word of each allowed command, for "you can say…".
  static List<String> examplesFor(Set<VoiceCommand> allowed) => [
        for (final entry in kVoiceKeywords.entries)
          if (allowed.contains(entry.key) && entry.value.isNotEmpty)
            entry.value.first,
      ].take(4).toList();

  @override
  void dispose() {
    _disposed = true;
    _commands.close();
    super.dispose();
  }
}
