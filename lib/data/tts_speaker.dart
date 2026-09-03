import 'package:flutter_tts/flutter_tts.dart';

import '../core/speech/speaker.dart';

/// [Speaker] backed by the platform engine.
class TtsSpeaker implements Speaker {
  TtsSpeaker({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;

  String? _last;

  @override
  String? get lastSpoken => _last;

  @override
  Future<void> repeat() async {
    final last = _last;
    // Deliberately does not overwrite _last, so repeat can be said twice.
    if (last == null) {
      await _say(kNothingToRepeat);
      return;
    }
    await _say(last);
  }

  Future<void> _say(String text) async {
    await _ensureReady();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _tts.setLanguage('en-US');
    // Slower than the platform default. The default is tuned for people
    // glancing at a screen while it talks; here it is the only channel.
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  @override
  Future<void> speak(String text) async {
    _last = text;
    await _say(text);
  }

  @override
  Future<void> speakLines(List<String> lines) async {
    _last = lines.join(' ');
    await _ensureReady();
    await _tts.stop();
    for (final line in lines) {
      await _tts.speak(line);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  @override
  Future<void> stop() => _tts.stop();
}
