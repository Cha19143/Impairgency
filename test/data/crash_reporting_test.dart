import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/data/crash_reporting.dart';

class Recorded implements CrashRecorder {
  final flutter = <Object>[];
  final uncaughtErrors = <Object>[];
  @override
  void flutterError(FlutterErrorDetails details) => flutter.add(details.exception);
  @override
  void uncaught(Object error, StackTrace stack) => uncaughtErrors.add(error);
  @override
  void handled(Object error, StackTrace? stack, {required String reason}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uncaught errors reach the recorder, from the framework and from outside it',
      () {
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    final previousRecorder = crashRecorder;
    addTearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
      crashRecorder = previousRecorder;
    });

    final recorded = Recorded();
    installCrashReporting(recorded);
    expect(crashRecorder, same(recorded));

    FlutterError.onError!(FlutterErrorDetails(
        exception: StateError('a build method threw'), silent: true));
    expect(recorded.flutter, hasLength(1));

    final handled = PlatformDispatcher.instance.onError!(
        StateError('an unawaited future threw'), StackTrace.current);
    expect(handled, isTrue);
    expect(recorded.uncaughtErrors, hasLength(1));
  });

  test('until installed, failures only go to the console', () {
    expect(const ConsoleRecorder(), isA<CrashRecorder>());
    expect(crashRecorder, isA<ConsoleRecorder>());
  });
}
