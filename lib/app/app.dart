import 'package:flutter/material.dart';

import '../data/prefs_session_store.dart';
import '../core/speech/speech_queue.dart';
import '../data/tts_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../admin/admin_theme.dart';
import 'router.dart';
import 'theme.dart';

class ImpairGencyApp extends StatefulWidget {
  const ImpairGencyApp({super.key});

  @override
  State<ImpairGencyApp> createState() => _ImpairGencyAppState();
}

class _ImpairGencyAppState extends State<ImpairGencyApp> {
  late final AppSession _session = AppSession(
    store: PrefsSessionStore(),
    // One queue for everything the app says. Hazards preempt; nothing else
    // cuts a sentence short. See core/speech/speech_queue.dart.
    speaker: SpeechQueue(engine: TtsEngine()),
  );
  late final _router = createRouter(_session);

  @override
  void initState() {
    super.initState();
    _session.load();
    _session.bindAuth();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      // MaterialApp's title becomes the browser tab title on web, overriding
      // the one in index.html.
      title: kIsWeb ? 'ImpairGency Admin' : 'ImpairGency',
      debugShowCheckedModeBanner: false,
      // The dashboard is the one surface not built under the app's
      // constraints - §4 allows it a denser interface, and it is read with
      // eyes rather than ears.
      theme: kIsWeb ? buildAdminTheme() : buildAppTheme(),
      routerConfig: _router,
      builder: (context, child) {
        // Text scaling is honoured rather than clamped - §4 asks for large text
        // and a user who has set 200% means it. Layouts are tested at 2.0x.
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
