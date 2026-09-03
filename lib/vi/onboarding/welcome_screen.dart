import 'package:flutter/material.dart';

import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Two doors, and the app says which is which before anyone touches it.
///
/// `cprwire` opened on a login form for an account that did not exist yet,
/// because registration was step 5 of 5. This is the fix for that, and the
/// reason everything after it has somewhere to be stored.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onCreateAccount,
    required this.onSignIn,
    this.speaker = const SilentSpeaker(),
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        title: 'Welcome to ImpairGency',
        body: const [
          'Sighted help, spoken aloud.',
          'Setting up takes about two minutes, and most of it can be skipped.',
        ],
        spokenSuffix: 'There are two choices. Create an account, or sign in.',
        actions: [
          ViButton(
            label: 'Create an account',
            detail: 'If this is your first time',
            icon: Icons.person_add_alt_1,
            onPressed: onCreateAccount,
          ),
          ViButton(
            label: 'Sign in',
            detail: 'If you already have one',
            icon: Icons.lock_outline,
            kind: ViButtonKind.secondary,
            onPressed: onSignIn,
          ),
        ],
      );
}
