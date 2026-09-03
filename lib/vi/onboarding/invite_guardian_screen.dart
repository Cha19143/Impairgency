import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/pairing/pairing_code.dart';
import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// The missing entry point.
///
/// `ui.pdf` has a Guardian Dashboard on page 17 and no screen anywhere that
/// connects a guardian to a user. Without this the second app is unreachable.
///
/// The code is read aloud, which is why its alphabet excludes every character
/// that rhymes with another — see `kSpeakSafeAlphabet`.
class InviteGuardianScreen extends StatelessWidget {
  const InviteGuardianScreen({
    super.key,
    required this.code,
    required this.onDone,
    required this.onSkip,
    this.speaker = const SilentSpeaker(),
  });

  final String code;
  final VoidCallback onDone;
  final VoidCallback onSkip;
  final Speaker speaker;

  /// Spelled out one character at a time, with the grouping said aloud.
  ///
  /// Reading "FH29MR47" as a word is useless to whoever is writing it down.
  String get spokenCode {
    final clean = normalisePairingCode(code);
    final first = clean.substring(0, 4).split('').join(', ');
    final second = clean.substring(4).split('').join(', ');
    return 'First four: $first. Then: $second.';
  }

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        step: 'Step 4 of 6',
        title: 'Invite a guardian',
        body: const [
          'Give this code to the person who will watch over you. They enter it '
              'in their own app.',
          'It works once, and it expires in thirty minutes.',
        ],
        spokenSuffix: 'Your code is. $spokenCode',
        extra: Column(
          children: [
            Semantics(
              label: 'Your invitation code. $spokenCode',
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 22),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.08),
                    border: Border.all(color: AppColors.cyan, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    spokenPairingCode(code),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          ViButton(
            label: 'Read the code again',
            icon: Icons.volume_up_outlined,
            kind: ViButtonKind.secondary,
            onPressed: () => speaker.speak(spokenCode),
          ),
          ViButton(
            label: "They've got it",
            icon: Icons.check,
            onPressed: onDone,
          ),
          ViButton(
            label: 'Skip — invite someone later',
            semanticLabel:
                'Skip. Nobody will be able to see your location or be alerted '
                'when you call for help.',
            kind: ViButtonKind.quiet,
            onPressed: onSkip,
          ),
        ],
      );
}
