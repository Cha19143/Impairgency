/// Runs [CreateAccountFlow] on the create-account screen.
///
/// Speech goes through the screen's [Speaker]. Listening goes through
/// [VoiceController.hearOnce], which waits until that speech has finished
/// before it opens the microphone. The password is never spoken, never
/// parsed, and never logged: only its length is read, and only to decide
/// whether it is long enough.
library;

import 'dart:async';

import '../../core/speech/speaker.dart';
import '../../core/voice/screen_flow.dart';
import '../../core/voice/speech_recognizer.dart';
import '../voice_controller.dart';

class CreateAccountVoiceFlow {
  CreateAccountVoiceFlow({
    required this.voice,
    required this.speaker,
    required this.setEmail,
    required this.passwordLength,
    required this.onPrompt,
    required this.onWatchPassword,
    required this.onFocusPassword,
    required this.onSubmit,
    required this.isMounted,
  });

  final VoiceController voice;
  final Speaker speaker;
  final void Function(String email) setEmail;

  /// How many characters are in the password field. The characters themselves
  /// stay in the field.
  final int Function() passwordLength;

  final void Function(String prompt) onPrompt;
  final void Function(bool watch) onWatchPassword;
  final void Function() onFocusPassword;
  final Future<String?> Function() onSubmit;
  final bool Function() isMounted;

  final CreateAccountFlow machine = CreateAccountFlow();

  var _token = 0;
  var _running = false;
  var _awaitingHear = false;
  var _touchDone = false;
  var _handlingPassword = false;

  void start() {
    final token = ++_token;
    unawaited(_run(token, machine.openingMove()));
  }

  void cancel() {
    _token++;
    _touchDone = false;
    _handlingPassword = false;
    unawaited(voice.stop());
  }

  /// The keyboard's done key, or a tap outside the password field.
  ///
  /// The typed characters are not read here. [passwordLength] counts them.
  void passwordFinished() {
    if (_handlingPassword) return;
    if (machine.step != CreateAccountStep.askPassword) return;
    _handlingPassword = true;
    _touchDone = true;
    if (_running) {
      if (_awaitingHear) unawaited(_stopUntilHeard());
      return;
    }
    final token = _token;
    final length = passwordLength();
    _touchDone = false;
    _handlingPassword = false;
    unawaited(_run(token, machine.advance(FlowCommand.done, passwordLength: length)));
  }

  Future<void> _stopUntilHeard() async {
    final token = _token;
    while (_touchDone && token == _token) {
      await voice.stop();
      await Future<void>.delayed(Duration.zero);
      if (!_touchDone || token != _token) return;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _run(int token, FlowMove move) async {
    _running = true;
    try {
      while (token == _token && isMounted()) {
        if (move.email != null) setEmail(move.email!);
        onWatchPassword(move.focusPassword);
        if (move.focusPassword) onFocusPassword();

        final utterance = move.lines.join(' ');
        if (utterance.isNotEmpty) onPrompt(utterance);

        if (move.submit) {
          final failure = await onSubmit();
          if (token != _token || !isMounted()) return;
          if (failure == null) return;
          move = machine.afterFailure(failure);
          continue;
        }

        if (!move.listen) {
          if (utterance.isNotEmpty) await speaker.speak(utterance);
          if (token != _token || !isMounted()) return;
          if (_touchDone && machine.step == CreateAccountStep.askPassword) {
            final length = passwordLength();
            _touchDone = false;
            _handlingPassword = false;
            move = machine.advance(
              FlowCommand.done,
              passwordLength: length,
            );
            continue;
          }
          if (move.stop || !move.continueAfter) return;
          move = machine.advance(FlowCommand.continued);
          continue;
        }

        _awaitingHear = true;
        final heard = await voice.hearOnce(
          utterance,
          listenFor: move.dictate ? kDictationWindow : kListenWindow,
          pauseFor: move.dictate ? kDictationPause : kPauseEndsPhrase,
          kind: move.dictate ? ListenKind.dictation : ListenKind.command,
        );
        _awaitingHear = false;
        if (token != _token || !isMounted()) return;

        if (_touchDone) {
          final length = passwordLength();
          _touchDone = false;
          _handlingPassword = false;
          move = machine.advance(FlowCommand.done, passwordLength: length);
          continue;
        }

        final command = interpretAccountReply(machine.step, heard);
        move = machine.advance(
          command,
          heard: command == FlowCommand.heard ? (heard ?? '') : '',
          passwordLength:
              command == FlowCommand.done ? passwordLength() : 0,
        );
      }
    } finally {
      _awaitingHear = false;
      if (token == _token) _running = false;
    }
  }
}
