import 'package:flutter/material.dart';

import '../data/prefs_session_store.dart';
import '../data/tts_speaker.dart';
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
    speaker: TtsSpeaker(),
  );
  late final _router = createRouter(_session);

  @override
  void initState() {
    super.initState();
    _session.load();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ImpairGency',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
      builder: (context, child) {
        // Text scaling is honoured rather than clamped - §4 asks for large text
        // and a user who has set 200% means it. Layouts are tested at 2.0x.
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
