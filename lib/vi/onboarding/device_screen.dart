import 'package:flutter/material.dart';

import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Last, and optional, and gating nothing.
///
/// In `ui.pdf` this was steps 2 and 3 of 5, ahead of the emergency contact, and
/// it refused to advance until you pressed a "Vibrate to Identify" button on
/// hardware that has never existed. Optional hardware must not stand in front
/// of the thing that could save someone's life.
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({
    super.key,
    required this.onHasDevice,
    required this.onNoDevice,
    required this.onSkip,
    this.speaker = const SilentSpeaker(),
  });

  final VoidCallback onHasDevice;
  final VoidCallback onNoDevice;
  final VoidCallback onSkip;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        step: 'Step 7 of 7',
        title: 'Do you have an ImpairGency device?',
        body: const [
          'This is optional. Scanning, guidance and emergency SOS all work on '
              'the phone by itself.',
        ],
        spokenSuffix: 'Say yes, no, or skip.',
        actions: [
          ViButton(
            label: 'I have one',
            icon: Icons.watch_outlined,
            onPressed: onHasDevice,
          ),
          ViButton(
            label: "I don't have one",
            icon: Icons.phone_iphone,
            kind: ViButtonKind.secondary,
            onPressed: onNoDevice,
          ),
          ViButton(
            label: 'Skip — ask me later',
            semanticLabel: 'Skip. You can connect a device later from settings.',
            kind: ViButtonKind.quiet,
            onPressed: onSkip,
          ),
        ],
      );
}
