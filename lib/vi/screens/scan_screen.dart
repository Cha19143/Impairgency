import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/location/location_fix.dart';
import '../../core/navigation/destination.dart';
import '../../core/navigation/journey_guide.dart';
import '../../core/navigation/map_services.dart';
import '../../core/speech/speaker.dart';
import '../../core/vision/detection.dart';
import '../../core/vision/faces.dart';
import '../../core/vision/friend_recognition.dart';
import '../../core/voice/voice_commands.dart';
import '../../data/scan_service.dart';
import '../voice_controller.dart';
import '../widgets/vi_button.dart';
import '../widgets/voice_mic_button.dart';

/// §2.A.1 and §2.A.3 — describing what is in front of the user.
///
/// The **Repeat** button is #50, and `ui.pdf` was right to ask for it: spoken
/// guidance goes past and there is no way to see it again. It is here as a
/// button, as a tap anywhere on the camera view, and as the spoken command
/// "repeat" — three routes to the same thing, because a user mid-walk may have
/// any one of them free.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.onBack,
    this.speaker = const SilentSpeaker(),
    this.service,
    this.voice,
    this.destination,
    this.positions,
    this.routing,
    this.onStopGuidance,
    this.onObstacle,
    this.friends,
    this.meetFriend,
  });

  final VoidCallback onBack;

  /// Where the user said they were going, if anywhere. With one, the screen
  /// also gives directions - behind hazards in the speech queue, always.
  final Destination? destination;

  /// Position readings while walking. Null means no directions, whatever
  /// [destination] says - a test, or a refused location permission.
  final Stream<LocationFix>? positions;

  /// Walking routes, turn by turn. Null means the straight-line direction
  /// only, as before routes existed.
  final RoutingService? routing;

  /// Clears the destination and keeps scanning.
  final VoidCallback? onStopGuidance;

  /// Something close enough to walk into was warned about, by name. The
  /// session tells the guardian, if the user said it may.
  final void Function(String label)? onObstacle;

  /// Takes priorities, because this is the one screen where two things can
  /// need saying at once and one of them is a hazard.
  final PrioritySpeaker speaker;

  /// Injected in tests so the screen can be exercised without a camera.
  final ScanService? service;

  /// Voice commands mid-walk: repeat, stop directions, where am I, back, help.
  /// Null hides the button.
  final VoiceController? voice;

  /// Saved friends, recognised and named - when the user has agreed to it.
  /// Null: nobody is recognised, and asking says how to turn it on.
  final FriendRecognition? friends;

  /// Someone to meet as soon as the camera is ready: "hello friend Sam", said
  /// on another screen.
  final String? meetFriend;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final ScanService _service = widget.service ?? ScanService();

  String _guidance = 'Starting…';
  String? _lastPhrase;
  DateTime? _lastSpokenAt;
  bool _ready = false;
  bool _refused = false;

  /// Kept from the first build: the router may build this screen again with
  /// a new one, and the faces watched belong to this.
  late final FriendRecognition? _friends = widget.friends;
  FaceWatch? _faceWatch;
  bool _facesReady = false;

  JourneyGuide? _guide;
  StreamSubscription<LocationFix>? _positions;
  Timer? _ticker;
  String? _direction;

  /// Set when directions are stopped from this screen. The route is not
  /// rebuilt for it - the router's go() to the location it is already at is
  /// a no-op - so [widget.destination] keeps its value and the screen has to
  /// forget it here: the link stayed, the arrival line stayed, and the tester
  /// pressed "Stop directions" three times to no visible effect.
  bool _directionsStopped = false;

  void _stopDirections() {
    _positions?.cancel();
    _positions = null;
    _ticker?.cancel();
    _guide?.stop();
    _guide = null;
    setState(() {
      _directionsStopped = true;
      _direction = null;
    });
    widget.speaker.announce(
      'Directions stopped. Still warning you about obstacles.',
      priority: SpeechPriority.navigation,
    );
    widget.onStopGuidance?.call();
  }

  VoiceScopeHandle? _voiceScope;

  @override
  void initState() {
    super.initState();
    _voiceScope = widget.voice?.attach(VoiceScope(
      commands: () => kScanCommands,
      onCommand: _onVoice,
    ));
    _begin();
    _beginDirections();
  }

  /// What Scan does itself when spoken to. "Only help works" was the tester's
  /// report: the rest went to the app-wide handler, which knew nothing about
  /// this screen.
  Future<bool> _onVoice(ParsedCommand heard) async {
    switch (heard.command) {
      case VoiceCommand.repeat:
        await _repeat();
        return true;
      case VoiceCommand.stopDirections:
        if (widget.destination == null || _directionsStopped) {
          await widget.speaker.speak('There are no directions to stop.');
        } else {
          _stopDirections();
        }
        return true;
      case VoiceCommand.rememberFriend:
        await _meet(heard.argument ?? '');
        return true;
      case VoiceCommand.whoIsHere:
        final friends = _friends;
        await widget.speaker.speak(friends == null
            ? kFacesOffPhrase
            : !_facesReady
                ? kFacesUnavailablePhrase
                : friends.whoIsHere());
        return true;
      case VoiceCommand.forgetFriend:
        final friends = _friends;
        final voice = widget.voice;
        // Without recognition on, the app-wide handler still deletes a face
        // saved earlier.
        if (friends == null || voice == null) return false;
        await widget.speaker
            .speak(await friends.forget(heard.argument ?? '', ask: voice.ask));
        return true;
      case VoiceCommand.back:
        // Leaving stops the obstacle warnings, so it is asked, not assumed:
        // "go back" is easy to say by accident mid-sentence.
        final answer = await widget.voice?.ask(
            'Leave scan? The obstacle warnings will stop. Say yes to leave, or '
            'no to stay.');
        if (!mounted) return true;
        if (answer?.command == VoiceCommand.yes) {
          widget.onBack();
        } else {
          await widget.speaker.speak('Staying on scan.');
        }
        return true;
      default:
        return false;
    }
  }

  /// A new destination while scanning - "take me to" said on this screen.
  /// The camera and the obstacle warnings carry on; only the directions
  /// change.
  @override
  void didUpdateWidget(ScanScreen old) {
    super.didUpdateWidget(old);
    if (widget.destination?.id == old.destination?.id) return;
    _positions?.cancel();
    _positions = null;
    _ticker?.cancel();
    _guide?.stop();
    _guide = null;
    _direction = null;
    _directionsStopped = false;
    _beginDirections();
  }

  /// "Hello friend Sam": asks Sam, then takes Sam's face down.
  ///
  /// The question is for the friend, and it is asked out loud with them in
  /// front of the phone: it is their face. No, or no answer, and nothing is
  /// kept.
  Future<void> _meet(String rawName) async {
    final name = normaliseFriendName(rawName);
    final friends = _friends;
    final voice = widget.voice;
    final watch = _faceWatch;
    if (name == null) {
      await widget.speaker.speak('Say hello friend, and then their name.');
      return;
    }
    if (friends == null) {
      await widget.speaker.speak(kFacesOffPhrase);
      return;
    }
    if (!_facesReady || watch == null || voice == null) {
      await widget.speaker.speak(kFacesUnavailablePhrase);
      return;
    }
    final answer = await voice.ask(friendConsentQuestion(name));
    if (!mounted) return;
    if (answer?.command != VoiceCommand.yes) {
      await widget.speaker.speak('Nothing was saved.');
      return;
    }
    await widget.speaker.speak(
        "Point the phone at $name's face, about an arm's length away, and "
        'hold still.');
    if (!mounted) return;
    setState(() => watch.enrolling = true);
    final result = await friends.enrol(name);
    if (!mounted) return;
    setState(() => watch.enrolling = false);
    await widget.speaker.speak(enrollmentResultPhrase(result, name: name));
  }

  void _beginDirections() {
    final to = widget.destination;
    final positions = widget.positions;
    if (to == null || positions == null) return;
    final guide = _guide = JourneyGuide(
      destination: to,
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
    _direction = guide.status;
    _positions = positions.listen(_onFix, onError: (_) {}, onDone: () {
      if (mounted && _direction != null) {
        setState(() => _direction = 'Directions stopped: no position.');
      }
    });
    if (widget.routing != null) {
      _ticker = Timer.periodic(const Duration(seconds: 5), (_) => _guide?.tick());
    }
  }

  void _onFix(LocationFix fix) {
    final guide = _guide;
    if (guide == null || !mounted) return;
    guide.update(fix);
    setState(() => _direction = guide.status);
  }

  Future<void> _reportMapProblem() async {
    try {
      await launchUrl(Uri.parse(kOsmFixTheMapUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      await widget.speaker.speak('The map page could not be opened.');
    }
  }

  Future<void> _begin() async {
    final modelOk = await _service.loadModel();
    if (!mounted) return;
    if (!modelOk) {
      setState(() => _guidance = 'Guidance is not available.');
      await widget.speaker.speak(
          'Sorry, guidance could not start. Everything else still works.');
      return;
    }

    final cameraOk = await _service.start(_onDetections);
    if (!mounted) return;
    if (!cameraOk) {
      setState(() {
        _refused = true;
        _guidance = 'The camera is off.';
      });
      await widget.speaker.speak(
          'The camera is turned off for this app. Turn it on in Settings to '
          'use guidance.');
      return;
    }

    setState(() {
      _ready = true;
      _guidance = kPathClear;
    });

    final friends = _friends;
    if (friends != null) {
      await friends.load();
      if (!mounted) return;
      final watch = _faceWatch = FaceWatch(onFaces: friends.onFaces);
      _facesReady = await _service.watchFaces(watch);
      if (!mounted) return;
    }
    final to = widget.destination;
    await widget.speaker.speak(to == null
        ? 'Guidance ready. Hold the phone up and walk slowly.'
        : widget.routing == null
            ? 'Guidance ready. Heading for ${to.label}. Directions follow the '
                'straight line to it, so listen for obstacles first. Hold the '
                'phone up and walk slowly.'
            : 'Guidance ready. Heading for ${to.label}. Finding a walking '
                'route; obstacle warnings come first. Hold the phone up and '
                'walk slowly.');
    final meet = widget.meetFriend;
    if (meet != null && mounted) unawaited(_meet(meet));
  }

  void _onDetections(List<Detection> detections) {
    final guidance = guidanceFor(detections);
    if (!mounted) return;
    setState(() => _guidance = guidance.phrase);
    // While a friend's face is being taken down, "person ahead" is the friend.
    // Only a hazard interrupts.
    if ((_faceWatch?.enrolling ?? false) && !guidance.urgent) return;

    final now = DateTime.now();
    if (!shouldSpeak(
      phrase: guidance.phrase,
      urgent: guidance.urgent,
      lastPhrase: _lastPhrase,
      lastSpokenAt: _lastSpokenAt,
      now: now,
    )) {
      return;
    }
    _lastPhrase = guidance.phrase;
    _lastSpokenAt = now;
    // A buzz as well as a word: someone in traffic may not hear it.
    if (guidance.urgent) HapticFeedback.heavyImpact();
    if (guidance.urgent && guidance.label != null) {
      widget.onObstacle?.call(guidance.label!);
    }
    // Hazards preempt whatever else is being said and are never restarted
    // while still in progress; ordinary descriptions wait their turn. The
    // queue holds that rule, not this screen.
    widget.speaker.announce(
      guidance.phrase,
      priority:
          guidance.urgent ? SpeechPriority.hazard : SpeechPriority.info,
    );
  }

  Future<void> _repeat() => widget.speaker.speak(
      _direction == null ? _guidance : '$_guidance. $_direction');

  @override
  void dispose() {
    // Not the microphone or the speech queue. Both are app-wide, and this runs
    // after the next screen has started: stopping them here cut off its first
    // sentence, cancelled its listening, and dropped any hazard still being
    // said. The router stops listening when the route changes instead.
    _voiceScope?.detach();
    _positions?.cancel();
    _ticker?.cancel();
    _guide?.stop();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _service.controller;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Semantics(
                label: _direction == null ? _guidance : '$_guidance. $_direction',
                button: true,
                onTap: _repeat,
                child: ExcludeSemantics(
                  // The whole view repeats. A user walking has one hand on a
                  // cane and cannot hunt for a button.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _repeat,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_ready && controller != null)
                          CameraPreview(controller)
                        else
                          Container(color: AppColors.navyRaised),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.navy.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _guidance,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    height: 1.3,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (_direction != null) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.navigation_outlined,
                                          color: AppColors.cyan, size: 22),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _direction!,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            height: 1.3,
                                            color: AppColors.cyan,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
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
                    detail: 'Say the last guidance again',
                    icon: Icons.replay,
                    onPressed: _repeat,
                  ),
                  if (widget.voice != null)
                    VoiceMicButton(
                      controller: widget.voice!,
                      only: kScanCommands,
                      detail: widget.destination == null
                          ? 'Say repeat, where am I, go back, or help'
                          : 'Say repeat, stop directions, where am I, or help',
                    ),
                  if (widget.destination != null &&
                      !_directionsStopped &&
                      widget.onStopGuidance != null)
                    ViButton(
                      label: 'Stop directions to ${widget.destination!.label}',
                      detail: 'Keeps warning you about obstacles',
                      kind: ViButtonKind.quiet,
                      onPressed: _stopDirections,
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
                  if (_refused)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Turn the camera on for ImpairGency in Settings to use '
                        'guidance. Everything else still works.',
                        style: TextStyle(
                            fontSize: 16,
                            height: 1.35,
                            color: AppColors.amber),
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
