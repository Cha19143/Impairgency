import 'package:flutter/material.dart';

import '../data/activity_repository.dart';
import '../data/geolocator_location_source.dart';
import '../data/location_history_repository.dart';
import '../data/location_sharer.dart';
import '../data/prefs_session_store.dart';
import '../core/speech/speech_queue.dart';
import '../data/tts_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../admin/admin_theme.dart';
import '../vi/widgets/voice_access.dart';
import 'router.dart';
import 'theme.dart';

class ImpairGencyApp extends StatefulWidget {
  const ImpairGencyApp({super.key});

  @override
  State<ImpairGencyApp> createState() => _ImpairGencyAppState();
}

class _ImpairGencyAppState extends State<ImpairGencyApp>
    with WidgetsBindingObserver {
  late final AppSession _session = AppSession(
    store: PrefsSessionStore(),
    // One queue for everything the app says. Hazards preempt; nothing else
    // cuts a sentence short. See core/speech/speech_queue.dart.
    speaker: SpeechQueue(engine: TtsEngine()),
    // The guardian's copy of where the user is. The session switches it on
    // and off with consent and with the app coming to the front.
    activity: ActivityRepository(),
    sharer: LocationSharer(
      source: const GeolocatorLocationSource(),
      sink: FirestoreLastFixSink(),
      recordHistory: (uid, fix) => LocationHistoryRepository()
          .record(uid, fix, sessionId: 'sharing'),
    ),
  );
  late final _router = createRouter(_session);

  /// Whether the device and Firebase have both answered yet. The router's
  /// first redirect runs against whatever the session holds at that moment;
  /// before load() the safety notice reads as unacknowledged, the redirect
  /// goes to /safety, and - because /safety stays reachable on purpose once
  /// acknowledged - nothing moves the user off it when the real value
  /// arrives. So every cold start re-read the notice to someone who had heard
  /// it. And before Firebase's first answer nobody is signed in, so a settled
  /// user heard Welcome for a second or two. The router is not built until
  /// both have landed.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.wait<void>([
      _session.load(),
      // Firebase answers in well under a second on a phone. If it never does,
      // the app opens anyway rather than sit on a blank screen for good.
      _session.firstAuth.timeout(const Duration(seconds: 5), onTimeout: () {}),
    ]).whenComplete(() {
      if (mounted) setState(() => _loaded = true);
    });
    _session.bindAuth();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _session.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      // The same dark ground as every screen, for the few frames it takes.
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: AppColors.navy),
      );
    }
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
        final page = child ?? const SizedBox.shrink();
        // The microphone, for every screen of the app: buttons pressed by
        // name, fields filled in by voice. The dashboard has none.
        if (kIsWeb) return page;
        return VoiceAccess(voice: _session.voice, child: page);
      },
    );
  }
}
