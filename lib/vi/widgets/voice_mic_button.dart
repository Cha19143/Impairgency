import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// What a tap does, by what the microphone is doing.
  ///
  /// During the app's own listening - the dashboard opens it after its
  /// prompt - a tap used to close the microphone without a word, which read as
  /// a button that does nothing. It now takes over: the app's window is shut,
  /// "Listening." is said, and a window of the user's own opens, whose
  /// failures are always said out loud. The word is said before the
  /// microphone opens so the microphone does not hear it.
  @visibleForTesting
  static Future<void> tap(VoiceController controller,
      {Set<VoiceCommand>? only}) async {
    if (controller.isBusy && !controller.isAutoListening) {
      await controller.stop();
      await controller.speaker.speak('Stopped listening.');
      return;
    }
    HapticFeedback.selectionClick();
    await controller.listenNow(
      only: only,
      cue: controller.isAutoListening ? 'Listening.' : null,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final phase = controller.phase;
          final examples =
              VoiceController.examplesFor(only ?? kEverydayCommands);
          // Hands-free: the microphone is open between phrases by itself, so
          // the button says so steadily rather than flickering between
          // "Listening…" and "Tap to speak" with every window.
          final handsFree = controller.handsFree &&
              controller.isHandsFreeActive &&
              (phase == VoicePhase.idle ||
                  (phase == VoicePhase.listening && controller.isAutoListening) ||
                  (phase == VoicePhase.preparing && controller.isAutoListening));
          final (label, hint, kind) = switch (phase) {
            _ when handsFree => (
                'Listening for commands',
                detail ?? 'Just speak - say ${examples.join(', ')}. Tap to '
                    'listen right now.',
                ViButtonKind.secondary,
              ),
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
                onPressed: () => tap(controller, only: only),
                pressByVoice: false,
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
