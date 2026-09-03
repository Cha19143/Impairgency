import 'package:flutter/material.dart';

import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Replaces `ui.pdf`'s "Vision Loss / Blind" question.
///
/// That one was clinically framed, mandatory, and changed nothing in the app.
/// This one asks something that changes behaviour — whether the screen stays
/// lit — and the answer is what the admin category is derived from, so §1.2
/// still gets its classification without anyone being asked to label
/// themselves.
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({
    super.key,
    required this.onChoose,
    required this.onSkip,
    this.speaker = const SilentSpeaker(),
  });

  /// True to keep the screen on.
  final void Function(bool screenStaysOn) onChoose;
  final VoidCallback onSkip;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        step: 'Step 2 of 6',
        title: 'Do you want the screen to stay on?',
        body: const [
          'This changes how much the app speaks, and whether the display '
              'sleeps while it is guiding you.',
        ],
        spokenSuffix: 'Keep it on, turn it off, or skip this question.',
        actions: [
          ViButton(
            label: 'Keep it on',
            detail: 'Useful if you can see some of the screen',
            icon: Icons.visibility_outlined,
            onPressed: () => onChoose(true),
          ),
          ViButton(
            label: 'Turn it off',
            detail: 'Speech only. Saves battery.',
            icon: Icons.volume_up_outlined,
            kind: ViButtonKind.secondary,
            onPressed: () => onChoose(false),
          ),
          ViButton(
            label: 'Skip for now',
            semanticLabel: 'Skip. The screen will stay on.',
            kind: ViButtonKind.quiet,
            onPressed: onSkip,
          ),
        ],
      );
}
