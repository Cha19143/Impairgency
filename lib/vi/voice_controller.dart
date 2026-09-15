import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/speech/speaker.dart';
import '../core/speech/speech_queue.dart';
import '../core/voice/echo.dart';
import '../core/voice/listening_policy.dart';
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

/// What one screen listens for, and what it does with what it hears.
///
/// A screen attaches one while it is showing. Commands it owns - Read Text's
/// "pause", Scan's "stop directions" - it handles itself; anything it passes
/// on goes to the app-wide [VoiceActions], so "help" works everywhere without
/// every screen having to say so.
class VoiceScope {
  const VoiceScope({
    this.commands,
    this.onCommand,
    this.onWords,
    this.exclusive = false,
    this.handsFree = true,
    this.echoOf,
    this.maxWords,
  });

  /// The vocabulary, asked each time the microphone opens - Read Text's
  /// changes while a page is being read. Null means [kEverydayCommands].
  final Set<VoiceCommand> Function()? commands;

  /// A command this screen does itself. Returns true when it did; false passes
  /// it on to the app-wide actions.
  final Future<bool> Function(ParsedCommand command)? onCommand;

  /// Sees what was said before any command is looked for, and returns true
  /// when it used it - Smart assistance hears a saved place's name said on its
  /// own.
  final Future<bool> Function(String words)? onWords;

  /// Nothing this screen does not handle goes anywhere else.
  final bool exclusive;

  /// Whether the microphone stays open on this screen when hands-free is on.
  final bool handsFree;

  /// What this screen says that the speech queue does not know about.
  final Iterable<String> Function()? echoOf;

  /// The most words a command may come in, when there is a limit. Read Text
  /// sets one while a page is read aloud: a page of words half-heard back
  /// through the microphone is not a command, and a command is short.
  final int Function()? maxWords;
}

/// Undoes one [VoiceController.attach], and only that one.
///
/// A screen's dispose() runs after the next screen has started. Detaching by
/// handle means a late dispose removes its own scope and never the new one's.
class VoiceScopeHandle {
  VoiceScopeHandle._(this._undo);

  final void Function() _undo;
  bool _detached = false;

  void detach() {
    if (_detached) return;
    _detached = true;
    _undo();
  }
}

class _Attached {
  _Attached(this.scope, this.route);
  final VoiceScope scope;
  final String? route;
}

/// The one path from a microphone to something happening.
///
/// permission → capture → recognition → [parseVoiceCommand] → the screen's
/// [VoiceScope], then [VoiceActions]. Every break in that chain ends in
/// [VoicePhase.failed] with a sentence that is both shown and spoken, because a
/// voice feature that fails silently is indistinguishable from one that does
/// not exist — which is exactly what the tester reported.
///
/// With [handsFree] on, the microphone reopens by itself after every phrase on
/// any screen whose scope asks for it, so nobody has to find "Tap to speak".
/// The app's own speech is recognised and ignored, hazard warnings close the
/// microphone until they have been said, and a microphone that keeps failing
/// is given up on once, out loud, rather than retried forever.
///
/// Screens that can act on a command themselves — the SOS countdown, which
/// listens for "cancel" — read [commands] instead of letting this dispatch.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.recognizer,
    required this.speaker,
    required this.actions,
    this.onNavigate,
    Future<void> Function(Duration delay)? wait,
    DateTime Function()? now,
  })  : _wait = wait ?? ((delay) => Future<void>.delayed(delay)),
        _now = now ?? DateTime.now {
    if (speaker case final SpeechActivity activity) {
      _activity = activity;
      _hazards = activity.hazardSpeaking.listen(_onHazard);
    }
  }

  final SpeechRecognizer recognizer;
  final Speaker speaker;

  /// Built fresh for each command, so it sees the current contact, guardian
  /// and device state rather than the ones at construction.
  final VoiceActions Function() actions;

  /// Where to go when a command has somewhere to go. Set by the router.
  void Function(String route)? onNavigate;

  final Future<void> Function(Duration delay) _wait;
  final DateTime Function() _now;

  SpeechActivity? _activity;
  StreamSubscription<bool>? _hazards;

  VoicePhase _phase = VoicePhase.idle;
  String? _transcript;
  String? _failureMessage;
  VoiceCommand? _lastCommand;
  ParsedCommand? _lastParsed;
  int _attempt = 0;
  bool _auto = false;

  VoicePhase get phase => _phase;

  /// Which attempt is current. Each [listen] and [stop] moves it on, so a
  /// caller that remembers it can tell whether its listening is still the
  /// one in progress.
  int get attempt => _attempt;

  /// The microphone is open because the app opened it, not because of a tap.
  bool get isAutoListening => isBusy && _auto;

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
  bool _networkSaid = false;

  // ---- scopes ----------------------------------------------------------

  final List<_Attached> _scopes = [];
  String? _route;

  /// Starts listening for [scope] on the current route.
  VoiceScopeHandle attach(VoiceScope scope) {
    final entry = _Attached(scope, _route);
    _scopes.add(entry);
    _rearm();
    return VoiceScopeHandle._(() {
      _scopes.remove(entry);
      // Only the hands-free window this scope was being listened for. Any
      // other listening - the SOS countdown's, opened by the next screen
      // before this one's dispose ran - is not this scope's to end.
      if (_active == null && _inLoopWindow && isAutoListening) {
        unawaited(stop());
      }
    });
  }

  /// The newest scope attached on the route the app is showing.
  VoiceScope? get _active {
    for (final entry in _scopes.reversed) {
      if (entry.route == _route) return entry.scope;
    }
    return null;
  }

  /// The route changed. What was listening stops; the next screen's scope, if
  /// it has one, takes over.
  void routeChanged(String path) {
    if (path == _route) return;
    _route = path;
    if (isBusy) unawaited(stop());
    _rearm();
  }

  // ---- hands-free ------------------------------------------------------

  bool _handsFree = false;
  bool _foreground = true;
  bool _looping = false;
  bool _inLoopWindow = false;
  bool _hazard = false;
  bool _gaveUp = false;
  int _holds = 0;

  /// Whether the microphone reopens by itself on screens that ask for it.
  bool get handsFree => _handsFree;
  set handsFree(bool on) {
    if (_handsFree == on) return;
    _handsFree = on;
    _gaveUp = false;
    if (!on && isAutoListening) unawaited(stop());
    notifyListeners();
    _rearm();
  }

  /// The hands-free microphone is being kept open right now.
  bool get isHandsFreeActive => _looping;

  /// The app went to the background or came back. A microphone left open
  /// behind another app is not something anyone agreed to.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      if (isBusy) unawaited(stop());
    } else {
      _gaveUp = false;
      _rearm();
    }
  }

  bool get _shouldLoop =>
      _handsFree &&
      _foreground &&
      !_disposed &&
      !_gaveUp &&
      !_hazard &&
      _holds == 0 &&
      (_active?.handsFree ?? false);

  void _rearm() {
    if (_shouldLoop && !_looping) unawaited(_loop());
  }

  Future<void> _loop() async {
    _looping = true;
    notifyListeners();
    var failures = 0;
    var networkFailures = 0;
    _networkSaid = false;
    try {
      while (_shouldLoop) {
        _inLoopWindow = true;
        final ListenOutcome outcome;
        try {
          outcome = await listen(
            auto: true,
            quiet: true,
            silenceSpeaker: false,
            listenFor: kHandsFreeWindow,
            pauseFor: kHandsFreePause,
          );
        } finally {
          _inLoopWindow = false;
        }
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
        if (delay == null) {
          _gaveUp = true;
          if (outcome == ListenOutcome.failed) {
            await speaker.speak(kHandsFreeStopped);
          }
          break;
        }
        await _wait(delay);
      }
    } finally {
      _looping = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// A hazard warning is being said. The microphone closes for it: an open
  /// recogniser can lower the volume of other audio, and a warning is not
  /// something to say quietly - or to hear back as a command.
  void _onHazard(bool speaking) {
    _hazard = speaking;
    if (speaking) {
      if (isAutoListening) unawaited(stop());
      return;
    }
    unawaited(_wait(kAfterHazard).then((_) => _rearm()));
  }

  /// Opens a window of the user's own - for a tap - after saying [cue], with
  /// hands-free listening held off until it is done.
  Future<ListenOutcome> listenNow({
    Set<VoiceCommand>? only,
    String? cue,
  }) async {
    _holds++;
    try {
      if (isBusy) await stop();
      if (cue != null) await speaker.speak(cue);
      return await listen(only: only, preempt: true);
    } finally {
      _holds--;
      _rearm();
    }
  }

  /// Asks [question] and listens for the answer: yes, no, next. Returns the
  /// answer, or null if none came. Works with hands-free off, because a
  /// question the app asks has to be answerable either way.
  Future<ParsedCommand?> ask(
    String question, {
    Set<VoiceCommand> answers = kAnswerCommands,
    Duration timeout = kListenWindow,
  }) async {
    _holds++;
    try {
      if (isBusy) await stop();
      await speaker.speak(question);
      final outcome = await listen(
        only: answers,
        dispatch: false,
        preempt: true,
        quiet: true,
        listenFor: timeout,
      );
      return outcome == ListenOutcome.acted ? _lastParsed : null;
    } finally {
      _holds--;
      _rearm();
    }
  }

  // ---- one window ------------------------------------------------------

  /// Listens for one phrase and acts on it.
  ///
  /// [only] restricts the vocabulary to what the current screen can do; left
  /// out, the screen's own [VoiceScope] decides.
  /// [dispatch] false means the caller will act on [commands] itself.
  /// [auto] is for listening the app started itself, after a prompt such as
  /// "Say scan, navigate, or help": hearing nothing is then not worth
  /// interrupting the user about, and a microphone that cannot work is
  /// explained out loud once, not on every screen. A tap on the button is
  /// never quiet.
  /// [quiet] is for the hands-free microphone and for questions: words that
  /// are not a command stay on screen rather than being said, because
  /// background conversation would otherwise produce a sentence every few
  /// seconds.
  /// [silenceSpeaker] stops the app talking so the microphone hears the
  /// user. The SOS countdown keeps talking — it is counting down — and
  /// passes false, with [echoOf] naming what it says: those words, heard
  /// back, are the app and not the user, and are taken out before matching.
  ///
  /// If the microphone is already open, this returns [ListenOutcome.busy] -
  /// unless it outranks what is listening: a tap outranks the app's own
  /// [auto] listening, and [preempt] outranks anything. The dashboard opens
  /// the microphone by itself after its prompt, and a tap in that window used
  /// to *close* it without a word, which is what "Tap to speak does nothing"
  /// was.
  Future<ListenOutcome> listen({
    Set<VoiceCommand>? only,
    bool dispatch = true,
    bool auto = false,
    bool quiet = false,
    bool silenceSpeaker = true,
    bool preempt = false,
    Iterable<String> Function()? echoOf,
    Duration listenFor = kListenWindow,
    Duration pauseFor = kPauseEndsPhrase,
  }) async {
    final wasBusy = isBusy;
    if (wasBusy && !preempt && !(_auto && !auto)) return ListenOutcome.busy;
    final attempt = ++_attempt;
    _auto = auto;
    _set(VoicePhase.preparing, transcript: null, failure: null);
    if (wasBusy) {
      await recognizer.cancel();
      if (attempt != _attempt) return ListenOutcome.cancelled;
    }

    // The screen's scope handles what is heard even when the caller narrows
    // the vocabulary - the microphone button passes the screen's own list.
    final scope = _active;
    final vocabulary = only ?? scope?.commands?.call() ?? kEverydayCommands;

    final readiness = await recognizer.prepare();
    if (attempt != _attempt) return ListenOutcome.cancelled;
    if (readiness != RecognizerReadiness.ready) {
      final explain = !auto || !_explainedOnce;
      _explainedOnce = true;
      await _fail(failureForReadiness(readiness),
          only: vocabulary, spoken: explain);
      return ListenOutcome.blocked;
    }

    // The microphone would otherwise hear the app talking. A hazard warning
    // is not narration and is left alone - which `stop()` did not do: it
    // dropped queued hazards along with everything else.
    if (silenceSpeaker) {
      if (speaker case final NarrationControl queue) {
        queue.clearNarration();
      } else {
        await speaker.stop();
      }
    }
    _set(VoicePhase.listening);
    final opened = _now();

    final hearing = await recognizer.listen(
      listenFor: listenFor,
      pauseFor: pauseFor,
      onPartial: (partial) {
        if (attempt != _attempt) return;
        _transcript = partial;
        notifyListeners();
      },
    );
    if (attempt != _attempt) return ListenOutcome.cancelled;

    switch (hearing) {
      case NotHeard(:final failure):
        final outcome = _outcomeFor(failure);
        if (failure == VoiceInputFailure.nothingHeard && (auto || quiet)) {
          _set(VoicePhase.idle);
          return outcome;
        }
        final spoken = switch (outcome) {
          _ when !quiet => true,
          ListenOutcome.blocked => !_explainedOnce,
          ListenOutcome.network => !_networkSaid,
          _ => false,
        };
        if (outcome == ListenOutcome.blocked) _explainedOnce = true;
        if (outcome == ListenOutcome.network) _networkSaid = true;
        await _fail(failure, only: vocabulary, spoken: spoken);
        return outcome;
      case Heard(:final words):
        _transcript = words;
        final said = <String>[
          ...?echoOf?.call(),
          ...?scope?.echoOf?.call(),
          // With the app still talking, what it said while the window was
          // open - and just before - is the app, not the person.
          if (!silenceSpeaker)
            ...?_activity?.spokenSince(opened.subtract(const Duration(seconds: 2))),
        ];
        final meant = said.isEmpty ? words : withoutEcho(words, said);
        if (meant.trim().isEmpty) {
          if (auto || quiet) {
            _set(VoicePhase.idle);
          } else {
            await _fail(VoiceInputFailure.nothingHeard, only: vocabulary);
          }
          return ListenOutcome.nothingHeard;
        }

        final limit = scope?.maxWords?.call();
        if (limit != null && spokenWords(meant).length > limit) {
          _set(VoicePhase.idle);
          return ListenOutcome.notUnderstood;
        }

        // A screen's own reading of the words never gets in the way of help.
        final onWords = scope?.onWords;
        final help = vocabulary.contains(VoiceCommand.help) &&
            parseVoiceCommand(meant, only: const {VoiceCommand.help}) != null;
        if (dispatch && onWords != null && !help && await onWords(meant)) {
          if (attempt == _attempt) _set(VoicePhase.idle);
          return ListenOutcome.acted;
        }

        final parsed = parseVoiceCommand(meant, only: vocabulary);
        if (parsed == null) {
          if (quiet) {
            _set(VoicePhase.idle);
          } else {
            await _fail(VoiceInputFailure.notUnderstood,
                only: vocabulary, transcript: words);
          }
          return ListenOutcome.notUnderstood;
        }
        _lastCommand = parsed.command;
        _lastParsed = parsed;
        _set(VoicePhase.heard);
        _commands.add(parsed.command);
        if (dispatch) await _dispatch(parsed, scope);
        if (attempt == _attempt && _phase == VoicePhase.heard) {
          _set(VoicePhase.idle);
        }
        return ListenOutcome.acted;
    }
  }

  static ListenOutcome _outcomeFor(VoiceInputFailure failure) =>
      switch (failure) {
        VoiceInputFailure.nothingHeard => ListenOutcome.nothingHeard,
        VoiceInputFailure.notUnderstood => ListenOutcome.notUnderstood,
        VoiceInputFailure.network => ListenOutcome.network,
        VoiceInputFailure.microphoneDenied ||
        VoiceInputFailure.microphoneBlocked ||
        VoiceInputFailure.unavailable =>
          ListenOutcome.blocked,
        VoiceInputFailure.failed => ListenOutcome.failed,
      };

  Future<void> _dispatch(ParsedCommand parsed, VoiceScope? scope) async {
    final own = scope?.onCommand;
    if (own != null && await own(parsed)) return;
    if (scope?.exclusive ?? false) return;
    final outcome =
        await actions().handle(parsed.command, argument: parsed.argument);
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
          if (allowed.contains(entry.key) &&
              entry.value.isNotEmpty &&
              !kArgumentCommands.contains(entry.key))
            entry.value.first,
      ].take(4).toList();

  @override
  void dispose() {
    _disposed = true;
    unawaited(_hazards?.cancel());
    _commands.close();
    super.dispose();
  }
}
