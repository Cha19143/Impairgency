/// Runs [VerifyEmailFlow] on the check-your-email screen.
///
/// Speech goes through the screen's [Speaker]. Listening goes through
/// [VoiceController.hearOnce], which holds the hands-free loop off until the
/// answer has been heard. The screen's existing check, resend, and sign-out
/// handlers are called as they are. This does not replace them.
library;

import 'dart:async';

import '../../core/speech/speaker.dart';
import '../../core/voice/verify_email_flow.dart';
import '../../data/auth_service.dart';
import '../voice_controller.dart';

class VerifyEmailVoiceFlow {
  VerifyEmailVoiceFlow({
    required this.voice,
    required this.speaker,
    required this.email,
    required this.linkSent,
    required this.onPrompt,
    required this.onCheck,
    required this.onResend,
    required this.onUseDifferentEmail,
    required this.isMounted,
  });

  final VoiceController voice;
  final Speaker speaker;
  final String? Function() email;
  final bool Function() linkSent;
  final void Function(String prompt) onPrompt;

  /// The screen's check. Null when the screen went away mid-check.
  final Future<VerificationCheck?> Function() onCheck;

  /// The screen's resend. True when a new link was sent, false when the
  /// handler already spoke a cooldown or a refusal, null when the screen
  /// went away.
  final Future<bool?> Function() onResend;

  final void Function() onUseDifferentEmail;
  final bool Function() isMounted;

  final VerifyEmailFlow machine = VerifyEmailFlow();

  var _token = 0;
  var _awaitingHear = false;
  var _away = false;
  var _cancelled = false;
  var _started = false;
  Future<void> _pending = Future<void>.value();

  void _enqueue(Future<void> Function() action) {
    _pending = _pending.then((_) async {
      try {
        await action();
      } catch (_) {
        // One failed question must not stop the next resume from running.
      }
    });
  }

  void start() {
    if (_cancelled) return;
    _enqueue(() async {
      if (_cancelled || _away || !isMounted()) return;
      _started = true;
      _sync();
      final token = ++_token;
      await _run(token, machine.opening());
    });
  }

  /// The app left the foreground. Speech and the microphone both stop, and
  /// a silence caused by that stop is not counted as a missed answer.
  void pause() {
    if (_cancelled || _away) return;
    _away = true;
    _token++;
    unawaited(speaker.stop());
    unawaited(voice.stop());
  }

  /// Back in the foreground. The current question is asked once, unless the
  /// screen has already been removed. Waits until the paused question has
  /// released the microphone, so two questions are never open together.
  void resume() {
    if (_cancelled || !_away) return;
    _away = false;
    _enqueue(() async {
      await Future<void>.delayed(Duration.zero);
      if (_cancelled || _away || !isMounted()) return;
      _sync();
      final token = ++_token;
      final first = !_started;
      _started = true;
      await _run(token, first ? machine.opening() : machine.reask());
    });
  }

  /// The screen is gone. The microphone is released. The speaker is left
  /// alone so a confirmation the router has already started is not cut off.
  void cancel() {
    _cancelled = true;
    _away = false;
    _token++;
    if (_awaitingHear) unawaited(voice.stop());
  }

  void _sync() => machine.sync(email: email(), linkSent: linkSent());

  Future<void> _run(int token, VerifyEmailMove move) async {
    try {
      while (token == _token && isMounted() && !_cancelled) {
        if (move.check) {
          final result = await onCheck();
          if (token != _token || !isMounted() || _cancelled) return;
          if (result == null) {
            _sync();
            move = machine.reask();
            continue;
          }
          _sync();
          move = machine.afterChecked(
            verified: result == VerificationCheck.verified,
          );
          continue;
        }

        if (move.resend) {
          final sent = await onResend();
          if (token != _token || !isMounted() || _cancelled) return;
          if (sent == null) return;
          _sync();
          move = machine.afterResent(sent: sent);
          continue;
        }

        if (move.signOut) {
          if (token != _token || !isMounted() || _cancelled) return;
          onUseDifferentEmail();
          return;
        }

        final utterance = move.lines.join(' ');
        if (utterance.isNotEmpty) onPrompt(utterance);

        if (!move.listen) {
          if (utterance.isNotEmpty) await speaker.speak(utterance);
          if (token != _token || !isMounted() || _cancelled) return;
          return;
        }

        _awaitingHear = true;
        final heard = await voice.hearOnce(utterance);
        _awaitingHear = false;
        if (token != _token || !isMounted() || _cancelled) return;

        move = machine.advance(interpretVerifyEmailReply(machine.step, heard));
      }
    } finally {
      _awaitingHear = false;
    }
  }
}
