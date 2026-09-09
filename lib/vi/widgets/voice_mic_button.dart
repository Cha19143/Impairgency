import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/voice/voice_commands.dart';
import '../voice_controller.dart';
import 'vi_button.dart';

/// The microphone, as a button that says what it is doing.
///
/// `ui.pdf` drew a microphone icon on ten screens and none of them did
/// anything. This is the one that does, and it is a full-size [ViButton]
/// rather than an icon because someone sweeping a screen they cannot see
/// needs a target they can find.
///
/// The status is a live region, so a screen reader announces "Listening" and
/// "Heard: scan" without focus having to move — and so a failure is announced
/// twice, once by the speaker and once by the reader, which is the right
/// number of times for the reason voice did not work.
class VoiceMicButton extends StatelessWidget {
  const VoiceMicButton({
    super.key,
    required this.controller,
    this.only,
    this.detail,
  });

  final VoiceController controller;

  /// What this screen can act on. Defaults to the everyday vocabulary.
  final Set<VoiceCommand>? only;

  /// What to say under the button when idle. Defaults to the first few
  /// words the current vocabulary accepts.
  final String? detail;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final phase = controller.phase;
          final examples =
              VoiceController.examplesFor(only ?? kEverydayCommands);
          final (label, hint, kind) = switch (phase) {
            VoicePhase.idle => (
                'Tap to speak',
                detail ?? 'Say ${examples.join(', ')}',
                ViButtonKind.secondary,
              ),
            VoicePhase.preparing => (
                'Getting ready…',
                'Checking the microphone',
                ViButtonKind.secondary,
              ),
            VoicePhase.listening => (
                'Listening…',
                controller.transcript?.isNotEmpty == true
                    ? 'Heard so far: ${controller.transcript}'
                    : 'Say a command now',
                ViButtonKind.primary,
              ),
            VoicePhase.heard => (
                'Heard: ${controller.transcript ?? ''}',
                'Doing that now',
                ViButtonKind.primary,
              ),
            VoicePhase.failed => (
                'Voice did not work. Tap to try again',
                null,
                ViButtonKind.secondary,
              ),
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ViButton(
                label: label,
                detail: hint,
                icon: phase == VoicePhase.listening
                    ? Icons.mic
                    : Icons.mic_none_outlined,
                kind: kind,
                onPressed: controller.isBusy
                    ? controller.stop
                    : () => controller.listen(only: only),
              ),
              if (phase == VoicePhase.failed &&
                  controller.failureMessage != null)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      controller.failureMessage!,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.35,
                        color: AppColors.amber,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}
