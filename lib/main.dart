import 'package:flutter/material.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is initialised here once `flutterfire configure` has been run
  // against the new project and lib/firebase_options.dart exists:
  //
  //   await Firebase.initializeApp(
  //     options: DefaultFirebaseOptions.currentPlatform,
  //   );
  //
  // Deliberately not wired yet, so the scaffold builds and runs on a clean
  // checkout. See docs/BUILD_PLAN.md, Phase 0.

  runApp(const ImpairGencyApp());
}
