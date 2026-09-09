import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/voice/speech_recognizer.dart';

/// [SpeechRecognizer] backed by the platform recogniser.
///
/// Permission is asked for explicitly, through `permission_handler`, rather
/// than left to the plugin's own prompt. The plugin reports a refused prompt
/// and a missing service the same way — `initialize` returns false — and
/// those two need different things said: one is fixed by tapping Allow, the
/// other by nothing the user can do.
class SttSpeechRecognizer implements SpeechRecognizer {
  SttSpeechRecognizer({SpeechToText? stt}) : _stt = stt ?? SpeechToText();

  final SpeechToText _stt;
  bool _initialised = false;

  Completer<VoiceHearing>? _session;
  String _partial = '';
  void Function(String partial)? _onPartial;

  @override
  Future<RecognizerReadiness> prepare() async {
    try {
      final mic = await _grant(Permission.microphone);
      if (mic != RecognizerReadiness.ready) return mic;
      // iOS gates recognition behind a second permission. Android has no
      // such thing, and asking it returns "restricted", which would read as
      // blocked to the mapping below.
      if (!kIsWeb && Platform.isIOS) {
        final speech = await _grant(Permission.speech);
        if (speech != RecognizerReadiness.ready) return speech;
      }
      if (_initialised) return RecognizerReadiness.ready;

      final ok = await _stt.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );
      if (!ok) {
        return _stt.lastError?.errorMsg == 'error_permission'
            ? RecognizerReadiness.microphoneDenied
            : RecognizerReadiness.unavailable;
      }
      _initialised = true;
      return RecognizerReadiness.ready;
    } catch (_) {
      return RecognizerReadiness.unavailable;
    }
  }

  Future<RecognizerReadiness> _grant(Permission permission) async {
    var status = await permission.status;
    if (status.isGranted || status.isLimited) return RecognizerReadiness.ready;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return RecognizerReadiness.microphoneBlocked;
    }
    status = await permission.request();
    if (status.isGranted || status.isLimited) return RecognizerReadiness.ready;
    return status.isPermanentlyDenied
        ? RecognizerReadiness.microphoneBlocked
        : RecognizerReadiness.microphoneDenied;
  }

  @override
  Future<VoiceHearing> listen({
    Duration listenFor = kListenWindow,
    Duration pauseFor = kPauseEndsPhrase,
    void Function(String partial)? onPartial,
  }) async {
    if (!_initialised) {
      final readiness = await prepare();
      if (readiness != RecognizerReadiness.ready) {
        return NotHeard(failureForReadiness(readiness));
      }
    }
    if (_stt.isListening) await _stt.cancel();

    final session = Completer<VoiceHearing>();
    _session = session;
    _partial = '';
    _onPartial = onPartial;

    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          listenFor: listenFor,
          pauseFor: pauseFor,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (_) {
      _settle(const NotHeard(VoiceInputFailure.failed));
    }

    // The platform sometimes neither errors nor finishes — a recogniser that
    // lost audio focus, for one. A window that never closes would leave the
    // button saying "Listening…" forever, which is the silent failure this
    // class exists to rule out.
    return session.future.timeout(
      listenFor + const Duration(seconds: 5),
      onTimeout: () {
        unawaited(_stt.stop());
        return _partial.trim().isEmpty
            ? const NotHeard(VoiceInputFailure.nothingHeard)
            : Heard(_partial);
      },
    );
  }

  void _onResult(SpeechRecognitionResult result) {
    _partial = result.recognizedWords;
    _onPartial?.call(_partial);
    if (result.finalResult) _settle(_fromWords(_partial));
  }

  void _onStatus(String status) {
    // 'notListening' arrives before the final result on Android; only 'done'
    // means the session has nothing more to say.
    if (status == 'done') _settle(_fromWords(_partial));
  }

  void _onError(SpeechRecognitionError error) {
    _settle(NotHeard(_failureFor(error.errorMsg)));
  }

  VoiceHearing _fromWords(String words) => words.trim().isEmpty
      ? const NotHeard(VoiceInputFailure.nothingHeard)
      : Heard(words.trim());

  static VoiceInputFailure _failureFor(String code) => switch (code) {
        'error_no_match' || 'error_speech_timeout' =>
          VoiceInputFailure.nothingHeard,
        'error_permission' => VoiceInputFailure.microphoneDenied,
        'error_network' ||
        'error_network_timeout' ||
        'error_server' ||
        'error_server_disconnected' =>
          VoiceInputFailure.network,
        'error_language_not_supported' ||
        'error_language_unavailable' ||
        'error_speech_recognizer_disabled' =>
          VoiceInputFailure.unavailable,
        _ => VoiceInputFailure.failed,
      };

  void _settle(VoiceHearing hearing) {
    final session = _session;
    if (session != null && !session.isCompleted) session.complete(hearing);
  }

  @override
  Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (_) {
      // Nothing was listening. That is the state cancel wants.
    }
    _settle(const NotHeard(VoiceInputFailure.failed));
  }
}
