import 'package:flutter/material.dart';

import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// A screen rather than a dialog, and a screen rather than a second tap.
///
/// Signing out is the one control on Settings that undoes work: it clears what
/// this phone knows, so the next way in is an email address and a password
/// typed by someone who cannot see the keyboard. A control like that cannot sit
/// one stray sweep away from the others — the buttons in this app are 88dp
/// precisely because they are found by sweeping rather than by aiming.
///
/// "Tap again to confirm" would be the smaller change and the wrong one: it
/// asks the user to hear a label change before their second tap lands, which is
/// exactly the assumption this app does not get to make.
class SignOutScreen extends StatelessWidget {
  const SignOutScreen({
    super.key,
    required this.onSignOut,
    required this.onCancel,
    this.speaker = const SilentSpeaker(),
  });

  final VoidCallback onSignOut;
  final VoidCallback onCancel;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        title: 'Sign out?',
        body: const [
          'Your account and everything in it stays where it is. This phone '
              'forgets it.',
          'To use ImpairGency again you will need to type your email address '
              'and your password.',
        ],
        spokenSuffix: 'Sign out, or stay signed in.',
        actions: [
          ViButton(
            label: 'Sign out',
            icon: Icons.logout,
            // Not the emergency red: this is not an emergency, and that colour
            // means one thing in this app.
            kind: ViButtonKind.secondary,
            onPressed: onSignOut,
          ),
          ViButton(
            label: 'Stay signed in',
            icon: Icons.arrow_back,
            onPressed: onCancel,
          ),
        ],
      );
}
