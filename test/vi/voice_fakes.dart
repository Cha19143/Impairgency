import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/vi/voice_actions.dart';
import 'package:impairgency/vi/voice_controller.dart';

/// A microphone whose every window stays open until the test closes it.
class OpenWindows implements SpeechRecognizer {
  OpenWindows({this.readiness = RecognizerReadiness.ready});

  RecognizerReadiness readiness;
  final sessions = <Completer<VoiceHearing>>[];
  int cancels = 0;

  bool get open => sessions.isNotEmpty && !sessions.last.isCompleted;

  @override
  Future<RecognizerReadiness> prepare() async => readiness;

  @override
  Future<VoiceHearing> listen({
    Duration listenFor = kListenWindow,
    Duration pauseFor = kPauseEndsPhrase,
    void Function(String partial)? onPartial,
    bool Function(String partial)? settleOn,
  }) {
    final window = Completer<VoiceHearing>();
    sessions.add(window);
    return window.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    for (final s in sessions) {
      if (!s.isCompleted) s.complete(const NotHeard(VoiceInputFailure.failed));
    }
  }

  /// Closes the open window with [hearing]. A widget test pumps after.
  void say(VoiceHearing hearing) => sessions.last.complete(hearing);

  /// Closes the open window with [hearing], and lets the app act on it.
  Future<void> hear(VoiceHearing hearing) async {
    say(hearing);
    await pumpEventQueue();
  }
}

/// Says everything at once.
class Recording implements Speaker {
  final said = <String>[];
  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;
  @override
  Future<void> repeat() async {}
  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);
  @override
  Future<void> stop() async {}
}

/// Finishes each sentence when the test says, so the app can be "talking".
class HeldEngine implements SpeechEngine {
  Completer<void>? _saying;
  final started = <String>[];

  @override
  Future<void> say(String text) {
    started.add(text);
    _saying = Completer<void>();
    return _saying!.future;
  }

  void finish() {
    final saying = _saying;
    _saying = null;
    if (saying != null && !saying.isCompleted) saying.complete();
  }

  @override
  Future<void> stop() async => finish();
}

class NoLocation implements LocationSource {
  const NoLocation();
  @override
  Future<LocationAvailability> availability() async =>
      LocationAvailability.denied;
  @override
  Future<LocationAvailability> requestPermission() async =>
      LocationAvailability.denied;
  @override
  Future<LocationFix?> currentFix({Duration timeout = Duration.zero}) async =>
      null;
  @override
  Future<LocationFix?> lastKnownFix() async => null;
}

/// A controller that waits for nothing between windows.
VoiceController voiceControllerFor(
  OpenWindows microphone,
  Speaker speaker, {
  List<String>? routes,
}) =>
    VoiceController(
      recognizer: microphone,
      speaker: speaker,
      actions: () => VoiceActions(
        location: const NoLocation(),
        fetchFix: () async =>
            (availability: LocationAvailability.denied, summary: null),
      ),
      onNavigate: routes?.add,
      wait: (_) async {},
    );
