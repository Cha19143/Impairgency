import 'package:flutter/material.dart';

import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Who is signing up.
///
/// There is one sign-in screen for both apps, which is right - an account is
/// an account. But there was one *registration* too, and it only knew how to
/// make a visually impaired user. A guardian who installed the app had no
/// door: the only way to become one was to already have an account made the
/// other way and then find the code screen by hand.
///
/// Two choices, both large, both spoken. The screen reader hears the role and
/// what it means before either is touched.
class ChooseRoleScreen extends StatelessWidget {
  const ChooseRoleScreen({
    super.key,
    required this.onVisuallyImpaired,
    required this.onGuardian,
    required this.onSignIn,
    this.speaker = const SilentSpeaker(),
  });

  final VoidCallback onVisuallyImpaired;
  final VoidCallback onGuardian;

  /// For someone who chose "create an account" and meant "sign in".
  final VoidCallback onSignIn;

  final Speaker speaker;

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        title: 'Who is this account for?',
        body: const [
          'ImpairGency has two sides: the app that guides, and the app that '
              'watches over.',
        ],
        spokenSuffix: 'Two choices. Visually impaired user, or guardian.',
        actions: [
          ViButton(
            label: 'Visually impaired user',
            detail: 'The app describes what is around you, guides you, and '
                'calls for help.',
            icon: Icons.visibility_off_outlined,
            onPressed: onVisuallyImpaired,
          ),
          ViButton(
            label: 'Guardian',
            detail: 'You watch over someone who uses the app. You will need '
                'the code from their phone.',
            icon: Icons.people_outline,
            kind: ViButtonKind.secondary,
            onPressed: onGuardian,
          ),
          ViButton(
            label: 'I already have an account',
            kind: ViButtonKind.quiet,
            onPressed: onSignIn,
          ),
        ],
      );
}
