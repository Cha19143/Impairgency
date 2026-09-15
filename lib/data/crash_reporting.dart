import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Where a failure goes, so that "crashes are reported" - §1.4, and what the
/// dashboard's System health screen tells administrators - is true.
///
/// `firebase_crashlytics` and its Gradle plugin were in the project from the
/// start, and nothing ever handed the SDK an error. On its own it catches a
/// crash in Android's native code; an error in the app's Dart code - which is
/// all of the app - went nowhere. First found in #77, whose fix no longer
/// applied after the speech queue replaced the file it edited.
abstract interface class CrashRecorder {
  /// An error the Flutter framework caught and nothing handled.
  void flutterError(FlutterErrorDetails details);

  /// An error that reached the top of an isolate: an unawaited future, a
  /// plugin channel that threw outside the framework.
  void uncaught(Object error, StackTrace stack);

  /// A failure the app handled and carried on through, that someone should
  /// still know about - a phone with no speech engine.
  void handled(Object error, StackTrace? stack, {required String reason});
}

/// Firebase Crashlytics.
class CrashlyticsRecorder implements CrashRecorder {
  const CrashlyticsRecorder();

  @override
  void flutterError(FlutterErrorDetails details) => unawaited(
      FirebaseCrashlytics.instance.recordFlutterFatalError(details));

  @override
  void uncaught(Object error, StackTrace stack) => unawaited(
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true));

  @override
  void handled(Object error, StackTrace? stack, {required String reason}) =>
      unawaited(FirebaseCrashlytics.instance
          .recordError(error, stack, reason: reason));
}

/// The console only: the web, the emulators, tests, and a debug run before
/// anything is installed.
class ConsoleRecorder implements CrashRecorder {
  const ConsoleRecorder();

  @override
  void flutterError(FlutterErrorDetails details) {}

  @override
  void uncaught(Object error, StackTrace stack) =>
      debugPrint('Uncaught error: $error\n$stack');

  @override
  void handled(Object error, StackTrace? stack, {required String reason}) =>
      debugPrint('Handled failure ($reason): $error');
}

/// Where failures go now. The console, until [installCrashReporting] runs.
CrashRecorder crashRecorder = const ConsoleRecorder();

/// Sends every uncaught error to [recorder], still printing each one: losing
/// the console output would trade one blind spot for another.
void installCrashReporting(CrashRecorder recorder) {
  crashRecorder = recorder;
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    recorder.flutterError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    recorder.uncaught(error, stack);
    return true;
  };
}
