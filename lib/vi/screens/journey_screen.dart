import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/clips/event_clip.dart';
import '../../core/guardian/obstacle_event.dart';
import '../../data/motion_source.dart';
import '../../core/location/course_tracker.dart';
import '../../core/location/location_fix.dart';
import '../../core/navigation/destination.dart';
import '../../core/navigation/journey_guide.dart';
import '../../core/navigation/map_services.dart';
import '../../core/navigation/route.dart';
import '../../core/speech/screen_reading.dart';
import '../../core/speech/speaker.dart';
import '../../core/speech/speech_queue.dart';
import '../../core/vision/friend_recognition.dart';
import '../../core/voice/voice_commands.dart';
import '../../data/scan_service.dart';
import '../fall_watch.dart';
import '../surroundings_watch.dart';
import '../voice_controller.dart';
import '../widgets/surroundings_preview.dart';
import '../widgets/vi_button.dart';
import '../widgets/voice_mic_button.dart';

/// Detection speech waits this long after a direction ends.
const Duration kNavSpeechGap = Duration(milliseconds: 500);

/// At the start, detection speech waits for the first direction, but not
/// longer than this (after the opening announcement), e.g. a weak GPS.
const Duration kFirstInstructionTimeout = Duration(seconds: 10);

/// What the map is drawn from.
class JourneyMapState {
  const JourneyMapState({
    required this.destination,
    this.fix,
    this.route,
    this.alongMetres,
  });

  final Destination destination;

  /// Where the user is, once known.
  final LocationFix? fix;

  /// The walking route's line, once found. Null for the straight line.
  final List<RoutePoint>? route;

  /// How far along [route] the user is.
  final double? alongMetres;
}

/// Draws the map. Injected in tests, which never fetch tiles.
typedef JourneyMapBuilder = Widget Function(JourneyMapState state);

/// §2.C and §2.A.7 — getting somewhere, on a map.
///
/// The testers asked to see the route. The directions are still spoken - the
/// map is for someone with some sight, and for whoever is walking beside them
/// - and the obstacle and people warnings carry on underneath, from the same
/// [SurroundingsWatch] Scan uses, with the camera in a corner.
/// Said when readings stop coming, or come as errors, while walking.
const String kPositionTroublePhrase = 'I am not getting your position right '
    'now. Check that location is on.';
const String kPositionEndedPhrase = 'Directions stopped: I no longer get your '
    'position. Check location permission.';

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({
    super.key,
    required this.destination,
    required this.onStop,
    required this.onBack,
    this.positions,
    this.routing,
    this.speaker = const SilentSpeaker(),
    this.service,
    this.voice,
    this.friends,
    this.onObstacle,
    this.onImportantObstacle,
    this.onFix,
    this.onGuidance,
    this.onArrived,
    this.onOffRoute,
    this.motion,
    this.onFallDetected,
    this.onFallFinished,
    this.onFallCancel,
    this.onFallHelp,
    this.captureClipFrames,
    this.onClipFrame,
    this.mapBuilder,
  });

  final Destination destination;

  /// Position readings while walking. Null means no directions - a refused
  /// location permission.
  final Stream<LocationFix>? positions;

  /// Walking routes, turn by turn. Null means the straight-line direction
  /// only.
  final RoutingService? routing;

  /// The directions are stopped. The router clears the destination and goes
  /// back to Scan, which carries on warning.
  final VoidCallback onStop;

  final VoidCallback onBack;
  final PrioritySpeaker speaker;
  final ScanService? service;
  final VoiceController? voice;
  final FriendRecognition? friends;
  final void Function(String label)? onObstacle;

  /// An urgent obstacle, for the guardian's history.
  final void Function(ObstacleNotice notice)? onImportantObstacle;

  /// Each position the directions used, for the journey's record.
  final void Function(LocationFix fix)? onFix;

  /// Each direction said, for the journey's record.
  final void Function(String sentence)? onGuidance;

  /// The destination was reached. Called once.
  final VoidCallback? onArrived;

  /// The walker left the route. [metresOff] is how far that reading was.
  final void Function(LocationFix fix, double metresOff)? onOffRoute;

  /// Accelerometer. Null in tests. Listening stops when this screen closes.
  final MotionSource? motion;
  final void Function()? onFallDetected;
  final Future<void> Function({required bool answered})? onFallFinished;
  final void Function()? onFallCancel;
  final void Function()? onFallHelp;

  /// When true, one gray frame is copied after each detection. Null skips it.
  final bool Function()? captureClipFrames;
  final void Function(GrayFrame)? onClipFrame;

  final JourneyMapBuilder? mapBuilder;

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  late final SurroundingsWatch _watch = SurroundingsWatch(
    speaker: widget.speaker,
    service: widget.service,
    voice: widget.voice,
    friends: widget.friends,
    onObstacle: (label) => widget.onObstacle?.call(label),
    onImportantObstacle: widget.onImportantObstacle,
    speechHeld: () => _falls?.checking ?? false,
    captureClipFrames: widget.captureClipFrames,
    onClipFrame: widget.onClipFrame,
  );

  FallWatch? _falls;

  JourneyGuide? _guide;
  StreamSubscription<LocationFix>? _positions;
  Timer? _ticker;
  LocationFix? _fix;
  String? _direction;
  bool _stopped = false;
  bool _arrived = false;
  bool _positionTroubleSaid = false;
  final _course = CourseTracker();
  VoiceScopeHandle? _voiceScope;

  // Detection speech waits for directions: until the first one has been said
  // (or the timeout), while one is being said, and for a short gap after it.
  bool _initialHold = true;
  int _saying = 0;
  bool _gapOpen = false;
  Timer? _gapTimer;
  Timer? _firstDirectionTimer;

  void _syncHold() {
    _watch.holdDetectionSpeech = _initialHold || _saying > 0 || _gapOpen;
  }

  /// Holds back detection speech from the moment a direction is queued until
  /// it has been said, plus a short gap.
  Future<T> _whileSaying<T>(Future<T> speech) async {
    _saying++;
    _gapTimer?.cancel();
    _gapOpen = false;
    _syncHold();
    try {
      return await speech;
    } finally {
      _saying--;
      _initialHold = false;
      if (_saying == 0 && mounted && !_stopped) {
        _gapOpen = true;
        _gapTimer = Timer(kNavSpeechGap, () {
          _gapOpen = false;
          _syncHold();
        });
      }
      _syncHold();
    }
  }

  @override
  void initState() {
    super.initState();
    final motion = widget.motion;
    if (motion != null) {
      _falls = FallWatch(
        motion: motion,
        speaker: widget.speaker,
        voice: widget.voice,
        onDetected: widget.onFallDetected ?? () {},
        onFinished: widget.onFallFinished ?? ({required bool answered}) async {},
        onCancel: widget.onFallCancel ?? () {},
        onHelp: widget.onFallHelp ?? () {},
      );
      _falls!.start();
    }
    _voiceScope = widget.voice?.attach(VoiceScope(
      commands: () => kJourneyCommands,
      onCommand: _onVoice,
    ));
    _syncHold();
    final to = widget.destination;
    _watch
        .start(
          readyPhrase: widget.routing == null
              ? 'Guidance ready. Heading for ${to.label}. Directions follow the '
                  'straight line to it, so listen for obstacles first. Hold the '
                  'phone up and walk slowly.'
              : 'Guidance ready. Heading for ${to.label}. Finding a walking '
                  'route; obstacle warnings come first. Hold the phone up and '
                  'walk slowly.',
          also: [
            'Repeat',
            'Say the directions and what is ahead again',
            if (widget.voice != null)
              ...openingMicLines(
                handsFree: widget.voice!.handsFree,
                detail: 'Say repeat, stop directions, where am I, or help',
              ),
            'Stop directions to ${to.label}',
            'Scan carries on warning you about obstacles',
            'Back',
          ],
        )
        .then((_) {
      if (!mounted || !_initialHold) return;
      _firstDirectionTimer = Timer(kFirstInstructionTimeout, () {
        _initialHold = false;
        _syncHold();
      });
    });
    _beginDirections();
  }

  /// A new destination while walking - "take me to" said on this screen. The
  /// camera and the warnings carry on; only the directions change.
  @override
  void didUpdateWidget(JourneyScreen old) {
    super.didUpdateWidget(old);
    if (widget.destination.id == old.destination.id) return;
    _endDirections();
    _beginDirections();
  }

  void _beginDirections() {
    final positions = widget.positions;
    final guide = _guide = JourneyGuide(
      destination: widget.destination,
      routing: widget.routing,
      // Navigation, not hazard: it waits for a warning to finish and never
      // cuts one off. The queue holds that rule. Detection speech is held
      // back while a direction is being said.
      say: (sentence) {
        widget.onGuidance?.call(sentence);
        unawaited(_whileSaying(widget.speaker
            .announce(sentence, priority: SpeechPriority.navigation)));
      },
      sayCountdown: (sentence) {
        widget.onGuidance?.call(sentence);
        final speaker = widget.speaker;
        if (speaker is SpeechQueue) {
          return _whileSaying(speaker.announceNavigation(sentence));
        }
        return _whileSaying(speaker
            .announce(sentence, priority: SpeechPriority.navigation)
            .then((_) => true));
      },
      onOffRoute: widget.onOffRoute,
      onChanged: () {
        if (mounted && _guide != null) {
          setState(() => _direction = _guide!.status);
        }
      },
    );
    _direction = positions == null
        ? 'Directions need your location, and it is off.'
        : guide.status;
    if (positions == null) return;
    _positions = positions.listen(_onFix, onError: (_) {
      // Location switched off, or the permission taken away, mid-walk.
      // Once: the stream may keep erroring.
      if (!mounted || _stopped || _positionTroubleSaid) return;
      _positionTroubleSaid = true;
      widget.speaker.announce(kPositionTroublePhrase,
          priority: SpeechPriority.navigation);
    }, onDone: () {
      if (!mounted || _stopped) return;
      setState(() => _direction = 'Directions stopped: no position.');
      widget.speaker.announce(kPositionEndedPhrase,
          priority: SpeechPriority.navigation);
    });
    if (widget.routing != null) {
      _ticker =
          Timer.periodic(const Duration(seconds: 5), (_) => _guide?.tick());
    }
  }

  void _endDirections() {
    _arrived = false;
    _positions?.cancel();
    _positions = null;
    _ticker?.cancel();
    _guide?.stop();
    _guide = null;
  }

  void _onFix(LocationFix raw) {
    final guide = _guide;
    if (guide == null || !mounted) return;
    _positionTroubleSaid = false;
    final fix = _course.withCourse(raw);
    guide.update(fix);
    widget.onFix?.call(fix);
    if (guide.mode == JourneyMode.arrived && !_arrived) {
      _arrived = true;
      widget.onArrived?.call();
    }
    setState(() {
      _fix = fix;
      _direction = guide.status;
    });
  }

  /// Stops the directions, once, and hands over to the router. Scan opens
  /// and carries on warning; for the second it takes the camera to start
  /// again, nothing is watching, and that is said rather than hidden.
  void _stop() {
    if (_stopped) return;
    _stopped = true;
    _endDirections();
    widget.speaker.announce(
      'Directions stopped. Scan carries on warning you about obstacles.',
      priority: SpeechPriority.navigation,
    );
    widget.onStop();
  }

  Future<bool> _onVoice(ParsedCommand heard) async {
    switch (heard.command) {
      case VoiceCommand.repeat:
        await _repeat();
        return true;
      case VoiceCommand.stopDirections:
        _stop();
        return true;
      case VoiceCommand.back:
        // Leaving stops the directions and the warnings both.
        final answer = await widget.voice?.ask(
            'Leave the directions to ${widget.destination.label}? The '
            'obstacle warnings will stop too. Say yes to leave, or no to '
            'stay.');
        if (!mounted) return true;
        if (answer?.command == VoiceCommand.yes) {
          widget.onBack();
        } else {
          await widget.speaker.speak('Staying with the directions.');
        }
        return true;
      default:
        return _watch.handleVoice(heard);
    }
  }

  String get _spoken =>
      [if (_direction != null) _direction!, _watch.guidance].join('. ');

  Future<void> _repeat() => widget.speaker.speak(_spoken);

  Future<void> _reportMapProblem() async {
    try {
      await launchUrl(Uri.parse(kOsmFixTheMapUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      await widget.speaker.speak('The map page could not be opened.');
    }
  }

  @override
  void dispose() {
    _gapTimer?.cancel();
    _firstDirectionTimer?.cancel();
    // Not the microphone or the speech queue: both are app-wide, and this
    // runs after the next screen has started.
    _voiceScope?.detach();
    _falls?.stop();
    _endDirections();
    _watch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final to = widget.destination;
    final map = JourneyMapState(
      destination: to,
      fix: _fix,
      route: _guide?.route?.geometry,
      alongMetres: _guide?.along,
    );

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: _watch,
                builder: (context, _) => Semantics(
                  label: _spoken,
                  button: true,
                  onTap: _repeat,
                  child: ExcludeSemantics(
                    // The whole view repeats, as on Scan: a hand on a cane
                    // cannot hunt for a button.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _repeat,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          (widget.mapBuilder ?? _defaultMap)(map),
                          Align(
                            alignment: Alignment.topCenter,
                            child: _Instruction(
                              direction: _direction,
                              guidance: _watch.guidance,
                            ),
                          ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            width: 120,
                            height: 160,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SurroundingsPreview(watch: _watch),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ViButton(
                    label: 'Repeat',
                    detail: 'Say the directions and what is ahead again',
                    icon: Icons.replay,
                    onPressed: _repeat,
                  ),
                  if (widget.voice != null)
                    VoiceMicButton(
                      controller: widget.voice!,
                      only: kJourneyCommands,
                      detail: 'Say repeat, stop directions, where am I, or '
                          'help',
                    ),
                  ViButton(
                    label: 'Stop directions to ${to.label}',
                    detail: 'Scan carries on warning you about obstacles',
                    kind: ViButtonKind.secondary,
                    icon: Icons.close,
                    onPressed: _stop,
                  ),
                  // OpenStreetMap's licence asks for the credit wherever its
                  // routes are used - and a wrong path is worth reporting.
                  if (_guide?.route != null)
                    TextButton(
                      onPressed: _reportMapProblem,
                      child: const Text(
                        'Walking route $kOsmAttribution. Report a map problem',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ),
                  ViButton(
                    label: 'Back',
                    kind: ViButtonKind.quiet,
                    onPressed: widget.onBack,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The next thing to do, big, and what the camera last said, under it.
class _Instruction extends StatelessWidget {
  const _Instruction({required this.direction, required this.guidance});

  final String? direction;
  final String guidance;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (direction != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.navigation_outlined,
                      color: AppColors.cyan, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      direction!,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.25,
                        fontWeight: FontWeight.bold,
                        color: AppColors.cyan,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              guidance,
              style: const TextStyle(
                fontSize: 19,
                height: 1.3,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
}

Widget _defaultMap(JourneyMapState state) => _JourneyMap(state: state);

/// OpenStreetMap tiles, the route, where the user is, and where they are
/// going - following the user as they walk.
class _JourneyMap extends StatefulWidget {
  const _JourneyMap({required this.state});

  final JourneyMapState state;

  @override
  State<_JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends State<_JourneyMap> {
  final _controller = MapController();
  bool _mapReady = false;

  LatLng get _centre {
    final fix = widget.state.fix;
    final to = widget.state.destination;
    return fix == null
        ? LatLng(to.latitude, to.longitude)
        : LatLng(fix.latitude, fix.longitude);
  }

  /// Moved, not rebuilt: a fix arrives every couple of metres, and a map
  /// rebuilt for each would reload its tiles each time.
  @override
  void didUpdateWidget(_JourneyMap old) {
    super.didUpdateWidget(old);
    final fix = widget.state.fix;
    if (_mapReady && fix != null && fix != old.state.fix) {
      _controller.move(_centre, _controller.camera.zoom);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final fix = state.fix;
    final route = state.route;
    final to = state.destination;
    final here = fix == null ? null : LatLng(fix.latitude, fix.longitude);

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _centre,
        initialZoom: 17,
        // Tapping the view repeats the directions; the map follows the user
        // by itself.
        interactionOptions:
            const InteractionOptions(flags: InteractiveFlag.none),
        onMapReady: () => _mapReady = true,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'ph.impairgency.app',
        ),
        if (route != null && route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [
                  for (final p in route) LatLng(p.latitude, p.longitude),
                ],
                color: AppColors.cyan,
                strokeWidth: 6,
                borderColor: AppColors.navy,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        if (fix != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: here!,
                radius: fix.accuracyMetres,
                useRadiusInMeter: true,
                color: AppColors.cyan.withValues(alpha: 0.15),
                borderColor: AppColors.cyan,
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(to.latitude, to.longitude),
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: const Icon(Icons.flag, size: 44, color: AppColors.red),
            ),
            if (here != null)
              Marker(
                point: here,
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cyan,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.navy, width: 3),
                  ),
                ),
              ),
          ],
        ),
        // The tiles are OpenStreetMap's, and its licence asks for the credit
        // on the map itself.
        RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(Uri.parse(kOsmCopyrightUrl),
                  mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      ],
    );
  }
}