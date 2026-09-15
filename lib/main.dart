import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'app/app.dart';
import 'app/emulator.dart';
import 'data/crash_reporting.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configures the SDK; it does not require a network, so a first run in
  // airplane mode still reaches the app rather than hanging on a splash screen.
  await Firebase.initializeApp(
    options: kUseEmulator
        ? DefaultFirebaseOptions.currentPlatform.copyWith(
            projectId: kEmulatorProjectId,
          )
        : DefaultFirebaseOptions.currentPlatform,
  );

  // §1.4, switched on. Not on the web, which has no Crashlytics and builds
  // only the dashboard; not under the emulator flag, whose project does not
  // exist. Collection is off in debug builds, so a developer's mistakes are
  // printed rather than counted among the users'.
  if (!kIsWeb && !kUseEmulator) {
    try {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      installCrashReporting(const CrashlyticsRecorder());
    } catch (e) {
      // Reporting that cannot start must not stop the app, SOS and all.
      debugPrint('Crash reporting is off: $e');
    }
  }

  if (kUseEmulator) {
    await FirebaseAuth.instance
        .useAuthEmulator(kEmulatorHost, kAuthEmulatorPort);
    FirebaseFirestore.instance
        .useFirestoreEmulator(kEmulatorHost, kFirestoreEmulatorPort);

    // Build the semantics tree from the first frame.
    //
    // Flutter web paints to a canvas, so the accessibility tree is the only
    // thing a browser test can read - and on this engine it is not enough to
    // click the "Enable accessibility" placeholder. That click is accepted (the
    // placeholder disappears) but no tree follows, so the tree has to be asked
    // for from inside the app. The handle is deliberately never disposed:
    // semantics stays on for the life of the process.
    //
    // Only under USE_EMULATOR, so a shipped build still builds the tree lazily,
    // exactly as it does today.
    SemanticsBinding.instance.ensureSemantics();
  }

  runApp(const ImpairGencyApp());
}
