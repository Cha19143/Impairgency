import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:impairgency/data/crash_reporting.dart';
import 'package:impairgency/data/tts_engine.dart';

class Reports implements CrashRecorder {
  final reasons = <String>[];
  @override
  void flutterError(FlutterErrorDetails details) {}
  @override
  void uncaught(Object error, StackTrace stack) {}
  @override
  void handled(Object error, StackTrace? stack, {required String reason}) =>
      reasons.add(reason);
}

const channel = MethodChannel('flutter_tts');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;
  late Reports reports;

  /// A phone's speech service, answering each method as [answer] says.
  void platform(Object? Function(MethodCall call) answer) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return answer(call);
    });
  }

  setUp(() {
    calls = [];
    reports = Reports();
  });

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('a phone with no speech engine stays open, silent, and says so once',
      () async {
    // Xiaomi's China ROMs, AOSP builds, an engine switched off: every call
    // throws. The first used to throw from the dashboard's first frame.
    platform((call) => throw PlatformException(code: 'no_engine'));
    final engine = TtsEngine(tts: FlutterTts(), problems: reports);

    await engine.say('Welcome to ImpairGency.');
    await engine.say('Say scan, read, or help.');
    await engine.stop();

    expect(engine.unavailable, isTrue);
    expect(calls, ['setLanguage'], reason: 'not asked again every sentence');
    expect(reports.reasons, hasLength(1));
    expect(reports.reasons.single, startsWith('setting up text-to-speech'));
  });

  test('no plugin at all is the same as no engine', () async {
    final engine = TtsEngine(tts: FlutterTts(), problems: reports);
    await engine.say('Hello.');
    expect(engine.unavailable, isTrue);
    expect(reports.reasons, hasLength(1));
  });

  test('one failed sentence is reported, and the next is still said', () async {
    var first = true;
    platform((call) {
      if (call.method == 'speak' && first) {
        first = false;
        throw PlatformException(code: 'busy');
      }
      return 1;
    });
    final engine = TtsEngine(tts: FlutterTts(), problems: reports);

    await engine.say('Stop. car right in front of you');
    await engine.say('Path looks clear');

    expect(engine.unavailable, isFalse);
    expect(calls.where((c) => c == 'speak'), hasLength(2));
    expect(reports.reasons, ['speaking']);
  });

  test('a working engine is set up once and reports nothing', () async {
    platform((call) => 1);
    final engine = TtsEngine(tts: FlutterTts(), problems: reports);
    await engine.say('One.');
    await engine.say('Two.');
    await engine.stop();
    expect(calls, [
      'setLanguage', 'setSpeechRate', 'setVolume', 'awaitSpeakCompletion',
      'speak', 'speak', 'stop',
    ]);
    expect(reports.reasons, isEmpty);
  });
}
