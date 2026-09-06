import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'app/app.dart';
import 'firebase_options.dart';

/// Points the app at the local Firebase emulators instead of the live project.
///
///     flutter run -d chrome --dart-define=USE_EMULATOR=true
///
/// A compile-time constant, so a release build cannot carry it in by accident -
/// the same shape as the START override in app/router.dart.
///
/// The project id is overridden along with the hosts. The Firestore emulator
/// only enforces the ruleset it was started with for the project it was started
/// as, so matching `demo-impairgency` - the id tool/test_rules.sh already uses -
/// is what makes the browser tests run against the real firestore.rules rather
/// than against an unguarded namespace.
const bool _useEmulator = bool.fromEnvironment('USE_EMULATOR');
const String _emulatorProjectId = 'demo-impairgency';
const String _emulatorHost = 'localhost';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configures the SDK; it does not require a network, so a first run in
  // airplane mode still reaches the app rather than hanging on a splash screen.
  await Firebase.initializeApp(
    options: _useEmulator
        ? DefaultFirebaseOptions.currentPlatform.copyWith(
            projectId: _emulatorProjectId,
          )
        : DefaultFirebaseOptions.currentPlatform,
  );

  if (_useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);

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
