import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../../core/vision/detection.dart';
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
  });

  final VoidCallback onBack;

  /// Takes priorities, because this is the one screen where two things can
  /// need saying at once and one of them is a hazard.
  final PrioritySpeaker speaker;

  /// Injected in tests so the screen can be exercised without a camera.
  final ScanService? service;

  /// "Repeat" and "help" by voice, mid-walk. Null hides the button.
  final VoiceController? voice;

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

  @override
  void initState() {
    super.initState();
    _begin();
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
    await widget.speaker
        .speak('Guidance ready. Hold the phone up and walk slowly.');
  }

  void _onDetections(List<Detection> detections) {
    final guidance = guidanceFor(detections);
    if (!mounted) return;
    setState(() => _guidance = guidance.phrase);

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
    // Hazards preempt whatever else is being said and are never restarted
    // while still in progress; ordinary descriptions wait their turn. The
    // queue holds that rule, not this screen.
    widget.speaker.announce(
      guidance.phrase,
      priority:
          guidance.urgent ? SpeechPriority.hazard : SpeechPriority.info,
    );
  }

  Future<void> _repeat() => widget.speaker.speak(_guidance);

  @override
  void dispose() {
    widget.voice?.stop();
    _service.dispose();
    widget.speaker.stop();
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
                label: _guidance,
                button: true,
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
                            child: Text(
                              _guidance,
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
                      detail: 'Say repeat, or help',
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
