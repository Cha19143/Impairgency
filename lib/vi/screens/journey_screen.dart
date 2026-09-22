import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/location/location_fix.dart';
import '../../core/navigation/destination.dart';
import '../../core/navigation/journey_guide.dart';
import '../../core/navigation/map_services.dart';
import '../../core/navigation/route.dart';
import '../../core/speech/speaker.dart';
import '../../core/vision/friend_recognition.dart';
import '../../core/voice/voice_commands.dart';
import '../../data/scan_service.dart';
import '../surroundings_watch.dart';
import '../voice_controller.dart';
import '../widgets/surroundings_preview.dart';
import '../widgets/vi_button.dart';
import '../widgets/voice_mic_button.dart';

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
  );

  JourneyGuide? _guide;
  StreamSubscription<LocationFix>? _positions;
  Timer? _ticker;
  LocationFix? _fix;
  String? _direction;
  bool _stopped = false;
  VoiceScopeHandle? _voiceScope;

  @override
  void initState() {
    super.initState();
    _voiceScope = widget.voice?.attach(VoiceScope(
      commands: () => kJourneyCommands,
      onCommand: _onVoice,
    ));
    final to = widget.destination;
    _watch.start(
      readyPhrase: widget.routing == null
          ? 'Guidance ready. Heading for ${to.label}. Directions follow the '
              'straight line to it, so listen for obstacles first. Hold the '
              'phone up and walk slowly.'
          : 'Guidance ready. Heading for ${to.label}. Finding a walking route; '
              'obstacle warnings come first. Hold the phone up and walk '
              'slowly.',
    );
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
      // cuts one off. The queue holds that rule.
      say: (sentence) => widget.speaker
          .announce(sentence, priority: SpeechPriority.navigation),
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
    _positions = positions.listen(_onFix, onError: (_) {}, onDone: () {
      if (mounted && !_stopped) {
        setState(() => _direction = 'Directions stopped: no position.');
      }
    });
    if (widget.routing != null) {
      _ticker =
          Timer.periodic(const Duration(seconds: 5), (_) => _guide?.tick());
    }
  }

  void _endDirections() {
    _positions?.cancel();
    _positions = null;
    _ticker?.cancel();
    _guide?.stop();
    _guide = null;
  }

  void _onFix(LocationFix fix) {
    final guide = _guide;
    if (guide == null || !mounted) return;
    guide.update(fix);
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
    // Not the microphone or the speech queue: both are app-wide, and this
    // runs after the next screen has started.
    _voiceScope?.detach();
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
