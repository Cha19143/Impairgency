/// One queue for everything the app says.
///
/// The bug this replaces: every screen talked to the engine directly, and the
/// engine's only verb was "stop whatever you are saying and say this". On the
/// scan screen a warning arrives with every camera frame, so "Stop, tree in
/// front of you" was restarted several times a second and the user heard
/// "Stop. Stop. Stop." and never the tree.
///
/// Pure Dart. The engine is injected, so the ordering rule — what interrupts
/// what — is tested without a speaker.
library;

import 'dart:async';

import 'speaker.dart';

class _Request {
  _Request(this.text, this.priority, this.seq, {required this.pauseAfter});

  final String text;
  final SpeechPriority priority;

  /// Arrival order, so equal priorities stay first-come first-served.
  final int seq;

  /// Silence to leave after this sentence, for multi-line notices.
  final Duration pauseAfter;

  final Completer<void> done = Completer<void>();

  void finish() {
    if (!done.isCompleted) done.complete();
  }
}

/// Stops what the app is narrating without touching what it is warning about.
///
/// Separate from [Speaker] on purpose: thirteen test fakes implement that, and
/// only the real queue knows which sentence is which.
abstract interface class NarrationControl {
  /// Drops pending information and navigation speech and cuts off the one in
  /// progress. A hazard, said or waiting, is left alone.
  void clearNarration();
}

/// What the app has been saying, for the microphone that is listening to the
/// same room.
///
/// A phone's speaker is a few centimetres from its microphone. With the
/// microphone left open, the recogniser transcribes the app as readily as the
/// person holding it; knowing what was said, and when, is how the app tells
/// the two apart.
abstract interface class SpeechActivity {
  /// Every sentence in progress, or finished at or after [since].
  List<String> spokenSince(DateTime since);

  /// True when a hazard warning starts being said, false when it ends.
  Stream<bool> get hazardSpeaking;
}

class _Said {
  _Said(this.text, this.start);
  final String text;
  final DateTime start;
  DateTime? end;
}

/// A [PrioritySpeaker] that serialises speech and enforces the preemption
/// rule documented on [PrioritySpeaker].
class SpeechQueue implements PrioritySpeaker, NarrationControl, SpeechActivity {
  SpeechQueue({
    required SpeechEngine engine,
    this.lineGap = const Duration(milliseconds: 350),
    DateTime Function()? now,
  })  : _engine = engine,
        _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// The last few sentences, with when they started and finished.
  final List<_Said> _history = [];
  static const int _historyLimit = 30;

  final StreamController<bool> _hazards = StreamController<bool>.broadcast();

  @override
  Stream<bool> get hazardSpeaking => _hazards.stream;

  @override
  List<String> spokenSince(DateTime since) => [
        for (final said in _history)
          if (said.end == null || !said.end!.isBefore(since)) said.text,
      ];

  final SpeechEngine _engine;

  /// Silence between the lines of [speakLines].
  final Duration lineGap;

  final List<_Request> _pending = [];
  _Request? _current;
  int _seq = 0;
  bool _draining = false;
  String? _last;

  @override
  String? get lastSpoken => _last;

  /// What is being said at this moment, or null.
  String? get current => _current?.text;

  /// What is waiting, in the order it will be said.
  List<String> get pending => _pending.map((r) => r.text).toList();

  @override
  Future<void> announce(String text,
      {required SpeechPriority priority}) {
    if (text.trim().isEmpty) return Future.value();

    if (priority == SpeechPriority.hazard) {
      // Already saying exactly this: let it finish rather than restart it.
      // This one line is the fix for the truncated warning.
      final current = _current;
      if (current != null &&
          current.priority == SpeechPriority.hazard &&
          current.text == text) {
        return current.done.future;
      }
      final queued = _pending
          .where((r) => r.priority == SpeechPriority.hazard && r.text == text)
          .firstOrNull;
      if (queued != null) return queued.done.future;
    }

    final request = _enqueue(text, priority, pauseAfter: Duration.zero);

    // A hazard is the only thing allowed to cut a sentence short — and it
    // cuts anything, including a different hazard, because a new danger is
    // new information.
    if (priority == SpeechPriority.hazard && _current != null) {
      unawaited(_engine.stop());
    }

    unawaited(_drain());
    return request.done.future;
  }

  @override
  Future<void> speak(String text) {
    _replaceInformational();
    return announce(text, priority: SpeechPriority.info);
  }

  @override
  Future<void> speakLines(List<String> lines) {
    final real = lines.where((l) => l.trim().isNotEmpty).toList();
    if (real.isEmpty) return Future.value();
    _replaceInformational();
    _Request? last;
    for (var i = 0; i < real.length; i++) {
      last = _enqueue(
        real[i],
        SpeechPriority.info,
        pauseAfter: i == real.length - 1 ? Duration.zero : lineGap,
      );
    }
    unawaited(_drain());
    return last!.done.future;
  }

  @override
  Future<void> repeat() {
    final last = _last;
    if (last == null) return speak(kNothingToRepeat);
    _replaceInformational();
    final request =
        _enqueue(last, SpeechPriority.info, pauseAfter: Duration.zero);
    unawaited(_drain());
    return request.done.future;
  }

  @override
  Future<void> stop() async {
    for (final r in _pending) {
      r.finish();
    }
    _pending.clear();
    if (_current != null) await _engine.stop();
  }

  @override
  void clearNarration() => _replaceInformational();

  /// The user did something, so whatever the app was telling them about
  /// before is stale. Drops pending narration and cuts it off if it is in
  /// progress — but never a hazard, which is about the street rather than
  /// the screen.
  void _replaceInformational() {
    _pending.removeWhere((r) {
      if (r.priority == SpeechPriority.hazard) return false;
      r.finish();
      return true;
    });
    final current = _current;
    if (current != null && current.priority != SpeechPriority.hazard) {
      unawaited(_engine.stop());
    }
  }

  _Request _enqueue(
    String text,
    SpeechPriority priority, {
    required Duration pauseAfter,
  }) {
    final request = _Request(text, priority, _seq++, pauseAfter: pauseAfter);
    _pending.add(request);
    // Highest priority first; within a priority, arrival order.
    _pending.sort((a, b) {
      final byPriority = b.priority.index.compareTo(a.priority.index);
      return byPriority != 0 ? byPriority : a.seq.compareTo(b.seq);
    });
    return request;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final request = _pending.removeAt(0);
        _current = request;
        _last = request.text;
        final said = _Said(request.text, _now());
        _history.add(said);
        if (_history.length > _historyLimit) _history.removeAt(0);
        final hazard = request.priority == SpeechPriority.hazard;
        if (hazard) _hazards.add(true);
        try {
          await _engine.say(request.text);
        } catch (_) {
          // An engine that throws must not take the queue down with it: the
          // next sentence may be the one that matters.
        }
        said.end = _now();
        if (hazard) _hazards.add(false);
        _current = null;
        request.finish();

        // The pause between lines of a notice. Skipped when a hazard is
        // waiting, because a hazard does not wait for anything.
        if (request.pauseAfter > Duration.zero &&
            _pending.isNotEmpty &&
            _pending.first.priority != SpeechPriority.hazard) {
          await Future<void>.delayed(request.pauseAfter);
        }
      }
    } finally {
      _draining = false;
    }
  }
}
