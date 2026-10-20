import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/clips/event_clip.dart';
import '../../core/guardian/obstacle_event.dart';
import '../../data/motion_source.dart';
import '../../core/speech/screen_reading.dart';
import '../../core/speech/speaker.dart';
import '../../core/vision/friend_recognition.dart';
import '../../core/voice/voice_commands.dart';
import '../../data/scan_service.dart';
import '../fall_watch.dart';
import '../surroundings_watch.dart';
import '../voice_controller.dart';
import '../widgets/surroundings_preview.dart';
import '../widgets/vi_button.dart';
import '../widgets/voice_mic_button.dart';

/// §2.A.1 and §2.A.3 — describing what is in front of the user.
///
/// Surroundings only. Directions moved to their own screen, with a map: the
/// testers asked for Scan to be about what is around them and for Smart
/// assistance to be about getting somewhere, and both still warn about
/// obstacles and people - see [SurroundingsWatch].
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
    this.onObstacle,
    this.onImportantObstacle,
    this.motion,
    this.onFallDetected,
    this.onFallFinished,
    this.onFallCancel,
    this.onFallHelp,
    this.captureClipFrames,
    this.onClipFrame,
    this.friends,
    this.meetFriend,
  });

  final VoidCallback onBack;

  /// Something close enough to walk into was warned about, by name.
  final void Function(String label)? onObstacle;

  /// An urgent obstacle, for the guardian's history. Separate from
  /// [onObstacle], which still feeds the activity card.
  final void Function(ObstacleNotice notice)? onImportantObstacle;

  /// Accelerometer. Null in tests, and on any screen that is not walking.
  final MotionSource? motion;
  final void Function()? onFallDetected;
  final Future<void> Function({required bool answered})? onFallFinished;
  final void Function()? onFallCancel;
  final void Function()? onFallHelp;

  /// When true, one gray frame is copied after each detection. Null skips it.
  final bool Function()? captureClipFrames;
  final void Function(GrayFrame)? onClipFrame;

  /// Takes priorities, because this is a screen where two things can need
  /// saying at once and one of them is a hazard.
  final PrioritySpeaker speaker;

  /// Injected in tests so the screen can be exercised without a camera.
  final ScanService? service;

  /// Voice commands mid-walk: repeat, where am I, back, help. Null hides the
  /// button.
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
  late final SurroundingsWatch _watch = SurroundingsWatch(
    speaker: widget.speaker,
    service: widget.service,
    voice: widget.voice,
    // Kept from the first build: the router may build this screen again with
    // a new one, and the faces watched belong to this.
    friends: widget.friends,
    onObstacle: (label) => widget.onObstacle?.call(label),
    onImportantObstacle: widget.onImportantObstacle,
    speechHeld: () => _falls?.checking ?? false,
    captureClipFrames: widget.captureClipFrames,
    onClipFrame: widget.onClipFrame,
  );

  FallWatch? _falls;

  VoiceScopeHandle? _voiceScope;

  @override
  void initState() {
    super.initState();
    _voiceScope = widget.voice?.attach(VoiceScope(
      commands: () => kScanCommands,
      onCommand: _onVoice,
    ));
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
    _watch.start(
      readyPhrase: 'Guidance ready. Hold the phone up and walk slowly.',
      meetFriend: widget.meetFriend,
      also: [
        'Repeat',
        'Say the last guidance again',
        if (widget.voice != null)
          ...openingMicLines(
            handsFree: widget.voice!.handsFree,
            detail: 'Say repeat, where am I, hello friend and a name, or help',
          ),
        'Back',
      ],
    );
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
        // Directions are on their own screen now; here there are none.
        await widget.speaker.speak('There are no directions to stop.');
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
        return _watch.handleVoice(heard);
    }
  }

  Future<void> _repeat() => widget.speaker.speak(_watch.guidance);

  @override
  void dispose() {
    // Not the microphone or the speech queue. Both are app-wide, and this runs
    // after the next screen has started: stopping them here cut off its first
    // sentence, cancelled its listening, and dropped any hazard still being
    // said. The router stops listening when the route changes instead.
    _voiceScope?.detach();
    _falls?.stop();
    _watch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _watch,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Semantics(
                  label: _watch.guidance,
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
                          SurroundingsPreview(watch: _watch),
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
                              child: Text(
                                _watch.guidance,
                                style: const TextStyle(
                                  fontSize: 24,
                                  height: 1.3,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
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
                        detail: 'Say repeat, where am I, hello friend and a '
                            'name, or help',
                      ),
                    if (_watch.refused)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Turn the camera on for ImpairGency in Settings to '
                          'use guidance. Everything else still works.',
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
      ),
    );
  }
}
