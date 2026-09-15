import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/voice/speech_recognizer.dart';

/// The parts of `speech_to_text` this app uses, behind a seam so the session
/// bookkeeping below can be tested without a platform channel.
abstract interface class SpeechBackend {
  bool get isListening;
  String? get lastErrorCode;

  Future<bool> initialize({
    required void Function(SpeechRecognitionError error) onError,
    required void Function(String status) onStatus,
  });

  Future<void> listen({
    required void Function(SpeechRecognitionResult result) onResult,
    required SpeechListenOptions options,
  });

  Future<void> stop();
  Future<void> cancel();
}

class SpeechToTextBackend implements SpeechBackend {
  SpeechToTextBackend([SpeechToText? stt]) : _stt = stt ?? SpeechToText();

  final SpeechToText _stt;

  @override
  bool get isListening => _stt.isListening;

  @override
  String? get lastErrorCode => _stt.lastError?.errorMsg;

  @override
  Future<bool> initialize({
    required void Function(SpeechRecognitionError error) onError,
    required void Function(String status) onStatus,
  }) =>
      _stt.initialize(onError: onError, onStatus: onStatus);

  @override
  Future<void> listen({
    required void Function(SpeechRecognitionResult result) onResult,
    required SpeechListenOptions options,
  }) =>
      _stt.listen(onResult: onResult, listenOptions: options);

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() => _stt.cancel();
}

/// Time to leave between one listening session ending and the next starting.
///
/// Android's recogniser tears a session down asynchronously. Start the next
/// one straight after a cancel and the old session's `ERROR_CLIENT` or "done"
/// can arrive while the new one is opening - and, reported as the new one's,
/// end it before a word is heard.
const Duration kRestartGap = Duration(milliseconds: 350);

/// [SpeechRecognizer] backed by the platform recogniser.
///
/// Permission is asked for explicitly, through `permission_handler`, rather
/// than left to the plugin's own prompt. The plugin reports a refused prompt
/// and a missing service the same way — `initialize` returns false — and
/// those two need different things said: one is fixed by tapping Allow, the
/// other by nothing the user can do.
class SttSpeechRecognizer implements SpeechRecognizer {
  SttSpeechRecognizer({
    SpeechBackend? backend,
    Future<RecognizerReadiness> Function()? permissions,
    DateTime Function()? now,
  })  : _backend = backend ?? SpeechToTextBackend(),
        _permissions = permissions,
        _now = now ?? DateTime.now;

  final SpeechBackend _backend;
  final Future<RecognizerReadiness> Function()? _permissions;
  final DateTime Function() _now;
  bool _initialised = false;

  Completer<VoiceHearing>? _session;
  String _partial = '';
  void Function(String partial)? _onPartial;

  /// Which session is current. Results carry theirs; status and error
  /// callbacks cannot, so they are only believed once the current session
  /// has said it is listening.
  int _generation = 0;
  bool _started = false;
  bool _retried = false;
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _endedAt = DateTime.fromMillisecondsSinceEpoch(0);
  SpeechListenOptions? _options;

  @override
  Future<RecognizerReadiness> prepare() async {
    try {
      final granted = await (_permissions ?? _askPermissions)();
      if (granted != RecognizerReadiness.ready) return granted;
      if (_initialised) return RecognizerReadiness.ready;

      final ok = await _backend.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );
      if (!ok) {
        debugPrint('Speech recognition would not initialise: '
            '${_backend.lastErrorCode}');
        return _backend.lastErrorCode == 'error_permission'
            ? RecognizerReadiness.microphoneDenied
            : RecognizerReadiness.unavailable;
      }
      _initialised = true;
      return RecognizerReadiness.ready;
    } catch (e) {
      debugPrint('Speech recognition unavailable: $e');
      return RecognizerReadiness.unavailable;
    }
  }

  Future<RecognizerReadiness> _askPermissions() async {
    final mic = await _grant(Permission.microphone);
    if (mic != RecognizerReadiness.ready) return mic;
    // iOS gates recognition behind a second permission. Android has no
    // such thing, and asking it returns "restricted", which would read as
    // blocked to the mapping below.
    if (!kIsWeb && Platform.isIOS) {
      final speech = await _grant(Permission.speech);
      if (speech != RecognizerReadiness.ready) return speech;
    }
    return RecognizerReadiness.ready;
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
    if (_backend.isListening) await _endBackend();

    final wait = kRestartGap - _now().difference(_endedAt);
    if (wait > Duration.zero) await Future<void>.delayed(wait);

    final session = Completer<VoiceHearing>();
    _session = session;
    _partial = '';
    _onPartial = onPartial;
    _retried = false;
    _options = SpeechListenOptions(
      listenFor: listenFor,
      pauseFor: pauseFor,
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
    await _start();

    // The platform sometimes neither errors nor finishes — a recogniser that
    // lost audio focus, for one. A window that never closes would leave the
    // button saying "Listening…" forever, which is the silent failure this
    // class exists to rule out.
    return session.future.timeout(
      listenFor + const Duration(seconds: 5),
      onTimeout: () {
        unawaited(_endBackend(stopOnly: true));
        return _partial.trim().isEmpty
            ? const NotHeard(VoiceInputFailure.nothingHeard)
            : Heard(_partial);
      },
    );
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _started = false;
    _startedAt = _now();
    try {
      await _backend.listen(
        onResult: (result) => _onResult(generation, result),
        options: _options!,
      );
    } catch (e) {
      debugPrint('Speech recognition did not start: $e');
      if (generation == _generation) {
        _settle(const NotHeard(VoiceInputFailure.failed));
      }
    }
  }

  void _onResult(int generation, SpeechRecognitionResult result) {
    if (generation != _generation) return;
    _started = true;
    _partial = result.recognizedWords;
    _onPartial?.call(_partial);
    if (result.finalResult) _settle(_fromWords(_partial));
  }

  void _onStatus(String status) {
    if (status == SpeechToText.listeningStatus) {
      _started = true;
      return;
    }
    // A "done" before this session has said it is listening is the previous
    // session being torn down.
    if (!_started) return;
    // 'notListening' arrives before the final result on Android; only 'done'
    // means the session has nothing more to say.
    if (status == SpeechToText.doneStatus) _settle(_fromWords(_partial));
  }

  void _onError(SpeechRecognitionError error) {
    final code = error.errorMsg;
    debugPrint('Speech recognition error: $code');
    final justStarted =
        !_started && _now().difference(_startedAt) < const Duration(seconds: 1);
    if (justStarted && _isBusyError(code)) {
      // Most likely the last session's teardown landing on this one. Try once
      // more after the gap rather than telling the user the microphone failed.
      if (!_retried && _session != null && !_session!.isCompleted) {
        _retried = true;
        unawaited(Future<void>.delayed(kRestartGap, _start));
      }
      return;
    }
    _settle(NotHeard(_failureFor(code)));
  }

  static bool _isBusyError(String code) =>
      code == 'error_client' ||
      code == 'error_busy' ||
      code == 'error_recognizer_busy';

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
    if (session == null || session.isCompleted) return;
    _endedAt = _now();
    session.complete(hearing);
  }

  Future<void> _endBackend({bool stopOnly = false}) async {
    try {
      if (stopOnly) {
        await _backend.stop();
      } else {
        await _backend.cancel();
      }
    } catch (_) {
      // Nothing was listening. That is the state wanted.
    }
    _generation++;
    _endedAt = _now();
  }

  @override
  Future<void> cancel() async {
    await _endBackend();
    _settle(const NotHeard(VoiceInputFailure.failed));
    _session = null;
  }
}
