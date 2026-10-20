import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_tts/flutter_tts.dart';

import '../core/speech/speaker.dart';
import 'crash_reporting.dart';

/// [SpeechEngine] backed by the platform's text-to-speech.
///
/// This used to be the whole speaker. It is now only the mouth: which
/// sentence comes next, and whether the current one may be cut off, is
/// decided by `SpeechQueue`, and this class's one job is to say a sentence
/// and to report — truthfully — when it has finished.
///
/// Every call into the platform is guarded. A speech engine is a service a
/// phone may simply not have: Xiaomi's China ROMs ship without Google's, many
/// AOSP builds have none, and a user can switch theirs off. There, every call
/// throws - and unguarded, the first one throws from the dashboard's
/// first frame, which looks exactly like the app opening and closing again.
/// For this app silence is close to fatal, but it has to be silence with the
/// screen still there: someone who can read it can still help. The failure
/// is reported once, not with every sentence (first found in #77).
class TtsEngine implements SpeechEngine, AdjustableSpeech {
  TtsEngine({FlutterTts? tts, this.speechRate = 0.45, CrashRecorder? problems})
      : _tts = tts ?? FlutterTts(),
        _rate = speechRate,
        _problems = problems;

  final FlutterTts _tts;

  /// Slower than the platform default. The default is tuned for people
  /// glancing at a screen while it talks; here it is the only channel.
  ///
  /// This stays 0.45 unless a caller passes something else. A change from
  /// Settings is stored in [_rate] and does not rewrite this default.
  final double speechRate;

  double _rate;

  /// Null means whatever `crashRecorder` is when something fails.
  final CrashRecorder? _problems;

  bool _ready = false;
  bool _unavailable = false;
  bool _reported = false;
  Completer<void>? _active;

  /// The phone could not set up speech at all, so nothing more is asked of
  /// it this run.
  bool get unavailable => _unavailable;

  Future<bool> _ensureReady() async {
    if (_ready) return true;
    if (_unavailable) return false;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(_rate);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (error, stack) {
      _unavailable = true;
      _report(error, stack,
          'setting up text-to-speech; speech is off until the app restarts');
      return false;
    }
    // Belt and braces. `awaitSpeakCompletion` makes `speak` return when the
    // engine says it is done; these handlers make it return when the engine
    // was cut off or failed, which not every platform reports through the
    // same future.
    _tts.setCompletionHandler(_settle);
    _tts.setCancelHandler(_settle);
    _tts.setErrorHandler((_) => _settle());
    _ready = true;
    return true;
  }

  /// Once per run: a phone that fails one sentence fails them all the same
  /// way, and a report per sentence would bury every other crash.
  void _report(Object error, StackTrace stack, String what) {
    if (_reported) return;
    _reported = true;
    (_problems ?? crashRecorder).handled(error, stack, reason: what);
  }

  void _settle() {
    final active = _active;
    if (active != null && !active.isCompleted) active.complete();
  }

  /// A ceiling on how long one sentence may hold the queue.
  ///
  /// If the platform engine never reports completion — no voice installed,
  /// audio focus lost, an emulator with no TTS — the next sentence, which may
  /// be a hazard, must not wait forever behind it. Generous for real speech
  /// at this rate; the fastest speaker manages roughly twelve characters a
  /// second, and this allows six.
  static Duration budgetFor(String text) => Duration(
      milliseconds: math.max(4000, 170 * text.length));

  @override
  Future<void> setSpeechRate(double rate) async {
    _rate = rate;
    if (!_ready || _unavailable) return;
    try {
      await _tts.setSpeechRate(_rate);
    } catch (error, stack) {
      _report(error, stack, 'changing the speech rate');
    }
  }

  @override
  Future<void> say(String text) async {
    if (!await _ensureReady()) return;
    final done = Completer<void>();
    _active = done;
    try {
      await Future.any<void>([
        // Caught here, not by the try below: a sentence cut off by the
        // handlers can still fail afterwards, when nothing is awaiting it,
        // and an error nobody awaits reaches the top of the app.
        _tts.speak(text).then((_) {}, onError: (Object error, StackTrace stack) {
          _report(error, stack, 'speaking');
        }),
        done.future,
      ]).timeout(budgetFor(text), onTimeout: _stopQuietly);
    } finally {
      if (identical(_active, done)) _active = null;
    }
  }

  @override
  Future<void> stop() async {
    if (_ready) await _stopQuietly();
    _settle();
  }

  Future<void> _stopQuietly() async {
    try {
      await _tts.stop();
    } catch (error, stack) {
      _report(error, stack, 'stopping speech');
    }
  }
}
