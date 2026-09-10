import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_tts/flutter_tts.dart';

import '../core/speech/speaker.dart';

/// [SpeechEngine] backed by the platform's text-to-speech.
///
/// This used to be the whole speaker. It is now only the mouth: which
/// sentence comes next, and whether the current one may be cut off, is
/// decided by `SpeechQueue`, and this class's one job is to say a sentence
/// and to report — truthfully — when it has finished.
class TtsEngine implements SpeechEngine {
  TtsEngine({FlutterTts? tts, this.speechRate = 0.45})
      : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  /// Slower than the platform default. The default is tuned for people
  /// glancing at a screen while it talks; here it is the only channel.
  final double speechRate;

  bool _ready = false;
  Completer<void>? _active;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(speechRate);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    // Belt and braces. `awaitSpeakCompletion` makes `speak` return when the
    // engine says it is done; these handlers make it return when the engine
    // was cut off or failed, which not every platform reports through the
    // same future.
    _tts.setCompletionHandler(_settle);
    _tts.setCancelHandler(_settle);
    _tts.setErrorHandler((_) => _settle());
    _ready = true;
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
  Future<void> say(String text) async {
    await _ensureReady();
    final done = Completer<void>();
    _active = done;
    try {
      await Future.any<void>([
        _tts.speak(text).then((_) {}),
        done.future,
      ]).timeout(budgetFor(text), onTimeout: () async {
        await _tts.stop();
      });
    } finally {
      if (identical(_active, done)) _active = null;
    }
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _settle();
  }
}
