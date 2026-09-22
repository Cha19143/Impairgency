import 'dart:async';

import '../core/voice/listening_policy.dart';
import '../core/voice/speech_recognizer.dart';
import '../core/voice/voice_commands.dart';
import 'voice_controller.dart';

/// Silence that ends a phrase while listening for "cancel". Shorter than a
/// command's: nobody says a sentence to stop an emergency call.
const Duration kCancelPause = Duration(seconds: 1);

/// How often to look again while the microphone is someone else's, or the app
/// is behind another one.
const Duration kCancelRecheck = Duration(milliseconds: 500);

/// Keeps the microphone open for "cancel" until told to stop.
///
/// One window was not enough. It opened as the SOS countdown began, heard the
/// countdown talking, took that out as the app's own voice, found nothing left
/// - and closed, with seconds still to go and nothing to open it again. A
/// "cancel" said after that went nowhere. This opens window after window until
/// the countdown, or the call it leads to, is over.
class CancelListener {
  CancelListener(
    this.controller, {
    required this.echoOf,
    this.window = kListenWindow,
    Future<void> Function(Duration delay)? wait,
  }) : _wait = wait ?? ((delay) => Future<void>.delayed(delay));

  final VoiceController controller;

  /// What the app says while this listens. Heard back, it is taken out.
  final Iterable<String> Function() echoOf;

  /// How long each window stays open.
  final Duration window;

  final Future<void> Function(Duration delay) _wait;

  bool _running = false;
  bool _stopped = false;
  int? _attempt;

  bool get isRunning => _running;

  /// Listens until [stop], a move to another screen, or a microphone that
  /// cannot work. Calling it again while it runs does nothing.
  Future<void> run() async {
    if (_running || _stopped) return;
    _running = true;
    final route = controller.route;
    var failures = 0;
    var networkFailures = 0;
    var first = true;
    try {
      while (!_stopped && controller.route == route) {
        // The first window takes the microphone from whatever had it. After
        // that, a window someone else opened is theirs, and one reopened
        // behind another app would be a microphone nobody agreed to.
        final taken = controller.isBusy && controller.attempt != _attempt;
        if (!controller.isForeground || (taken && !first)) {
          await _wait(kCancelRecheck);
          continue;
        }
        first = false;
        final listening = controller.listen(
          only: kCancellationCommands,
          dispatch: false,
          auto: true,
          // The countdown keeps counting, so the app keeps talking.
          silenceSpeaker: false,
          // Whatever else was listening, this outranks it: a countdown nobody
          // can cancel by voice is not cancellable by a user who has already
          // put the phone away.
          preempt: true,
          settleEarly: true,
          echoOf: echoOf,
          // "Cancel it", "please stop" - anything with a cancel word in it.
          wholePhrase: const {},
          listenFor: window,
          pauseFor: kCancelPause,
        );
        // listen() takes its attempt number before its first pause.
        _attempt = controller.attempt;
        final outcome = await listening;
        // A move to another screen stops the controller, and this with it.
        if (_stopped || controller.route != route) break;

        switch (outcome) {
          case ListenOutcome.failed:
            failures++;
          case ListenOutcome.network:
            networkFailures++;
          case ListenOutcome.busy || ListenOutcome.cancelled:
            break;
          default:
            failures = 0;
            networkFailures = 0;
        }
        final delay = delayBeforeListening(
          outcome,
          failuresInARow: outcome == ListenOutcome.network
              ? networkFailures - 1
              : failures - 1,
        );
        if (delay == null) break;
        await _wait(delay);
      }
    } finally {
      _running = false;
    }
  }

  /// Stops listening, for good. Only this listener's own window is closed:
  /// whatever opened the microphone since is not this listener's to end.
  Future<void> stop() async {
    _stopped = true;
    if (controller.isBusy && controller.attempt == _attempt) {
      await controller.stop();
    }
  }
}
