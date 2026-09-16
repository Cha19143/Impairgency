import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/data/stt_speech_recognizer.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// The platform recogniser as the plugin presents it: one pair of status and
/// error callbacks for the whole app, and a result callback per session.
class FakeBackend implements SpeechBackend {
  late void Function(SpeechRecognitionError) _onError;
  late void Function(String) _onStatus;
  final results = <void Function(SpeechRecognitionResult)>[];
  int listens = 0;
  int cancels = 0;

  @override
  bool isListening = false;

  @override
  String? get lastErrorCode => null;

  @override
  Future<bool> initialize({
    required void Function(SpeechRecognitionError error) onError,
    required void Function(String status) onStatus,
  }) async {
    _onError = onError;
    _onStatus = onStatus;
    return true;
  }

  @override
  Future<void> listen({
    required void Function(SpeechRecognitionResult result) onResult,
    required SpeechListenOptions options,
  }) async {
    listens++;
    results.add(onResult);
    isListening = true;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    isListening = false;
  }

  @override
  Future<void> stop() async => isListening = false;

  void status(String s) => _onStatus(s);
  void error(String code) => _onError(SpeechRecognitionError(code, true));
  void partial(String words, {int session = -1}) {
    final deliver = session < 0 ? results.last : results[session];
    deliver(SpeechRecognitionResult.init(
        [SpeechRecognitionWords(words, null, 1)], ResultType.partial));
  }

  void heard(String words, {int session = -1}) {
    final deliver = session < 0 ? results.last : results[session];
    deliver(SpeechRecognitionResult.init(
        [SpeechRecognitionWords(words, null, 1)], ResultType.finalResult));
  }
}

void main() {
  late FakeBackend backend;
  late DateTime clock;
  late SttSpeechRecognizer recognizer;

  setUp(() async {
    backend = FakeBackend();
    clock = DateTime.utc(2026, 9, 15);
    recognizer = SttSpeechRecognizer(
      backend: backend,
      permissions: () async => RecognizerReadiness.ready,
      now: () => clock,
    );
    expect(await recognizer.prepare(), RecognizerReadiness.ready);
  });

  test("a late 'done' from a cancelled session does not end the next one",
      () async {
    // The race behind a Tap to speak that listened for no time at all: the
    // old session's teardown arrives while the new one is opening.
    final first = recognizer.listen();
    await pumpEventQueue();
    backend.status(SpeechToText.listeningStatus);
    await recognizer.cancel();
    expect(await first, isA<NotHeard>());

    clock = clock.add(const Duration(seconds: 1));
    var settled = false;
    final second = recognizer.listen()..then((_) => settled = true);
    await pumpEventQueue();
    backend.status(SpeechToText.doneStatus); // the first session, tearing down
    await pumpEventQueue();
    expect(settled, isFalse);

    backend.status(SpeechToText.listeningStatus);
    backend.heard('scan');
    final hearing = await second;
    expect(hearing, isA<Heard>());
    expect((hearing as Heard).words, 'scan');
  });

  test('words from a cancelled session are not taken as the next one\'s',
      () async {
    final first = recognizer.listen();
    await pumpEventQueue();
    await recognizer.cancel();
    await first;

    clock = clock.add(const Duration(seconds: 1));
    var settled = false;
    final second = recognizer.listen()..then((_) => settled = true);
    await pumpEventQueue();
    backend.heard('help', session: 0);
    await pumpEventQueue();
    expect(settled, isFalse);

    backend.heard('scan');
    expect(((await second) as Heard).words, 'scan');
  });

  test('a busy error just after starting is retried once, not reported',
      () async {
    final hearing = recognizer.listen();
    await pumpEventQueue();
    backend.error('error_client');
    await Future<void>.delayed(kRestartGap + const Duration(milliseconds: 50));
    expect(backend.listens, 2, reason: 'started again after the gap');

    backend.status(SpeechToText.listeningStatus);
    backend.heard('where am I');
    expect(await hearing, isA<Heard>());
  });

  test('a real error still ends the session and says what it was', () async {
    final hearing = recognizer.listen();
    await pumpEventQueue();
    backend.status(SpeechToText.listeningStatus);
    backend.error('error_network');
    final result = await hearing;
    expect(result, isA<NotHeard>());
    expect((result as NotHeard).failure, VoiceInputFailure.network);
  });

  group('a hot word', () {
    test('settles the window on a partial, without waiting for the phrase',
        () async {
      // "Cancel" over the SOS countdown used to wait for a silence the
      // countdown never left.
      final seen = <String>[];
      final hearing = recognizer.listen(
        onPartial: seen.add,
        settleOn: (partial) => partial.contains('cancel'),
      );
      await pumpEventQueue();
      backend.status(SpeechToText.listeningStatus);
      backend.partial('calling mum');
      await pumpEventQueue();
      backend.partial('calling mum cancel');

      final result = await hearing;
      expect((result as Heard).words, 'calling mum cancel');
      expect(seen, ['calling mum', 'calling mum cancel']);
      expect(backend.cancels, 1, reason: 'that session is over');
    });

    test("its session's late final result is not the next window's",
        () async {
      final first = recognizer.listen(settleOn: (p) => p == 'teka');
      await pumpEventQueue();
      backend.status(SpeechToText.listeningStatus);
      backend.partial('teka');
      expect((await first as Heard).words, 'teka');

      clock = clock.add(const Duration(seconds: 1));
      var settled = false;
      final second = recognizer.listen()..then((_) => settled = true);
      await pumpEventQueue();
      backend.heard('teka', session: 0); // the first session, finishing late
      await pumpEventQueue();
      expect(settled, isFalse);

      backend.heard('scan');
      expect(((await second) as Heard).words, 'scan');
    });

    test('without one, a partial is only a partial', () async {
      var settled = false;
      final hearing = recognizer.listen()..then((_) => settled = true);
      await pumpEventQueue();
      backend.status(SpeechToText.listeningStatus);
      backend.partial('cancel');
      await pumpEventQueue();
      expect(settled, isFalse);

      backend.heard('cancel');
      expect(((await hearing) as Heard).words, 'cancel');
    });
  });
}
