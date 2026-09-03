import 'package:flutter/material.dart';

import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// One action.
///
/// `cprwire`'s version offered "GO TO DASHBOARD" *and* "GO TO LOGIN" — sending
/// a user who had just registered back to a sign-in screen. A completion screen
/// should have exactly one thing to do.
class AllSetScreen extends StatelessWidget {
  const AllSetScreen({
    super.key,
    required this.onStart,
    this.hasEmergencyContact = false,
    this.hasGuardian = false,
    this.speaker = const SilentSpeaker(),
  });

  final VoidCallback onStart;
  final bool hasEmergencyContact;
  final bool hasGuardian;
  final Speaker speaker;

  /// Says what is actually set up, rather than congratulating the user for
  /// finishing. If they skipped the emergency contact, this is the last honest
  /// chance to tell them what SOS can and cannot do.
  List<String> get _body => [
        if (hasEmergencyContact && hasGuardian)
          'Your emergency contact is saved and your guardian is invited.'
        else if (hasEmergencyContact)
          'Your emergency contact is saved. You have not invited a guardian yet.'
        else if (hasGuardian)
          'Your guardian is invited. You have not set an emergency contact, so '
              'SOS has nobody to call.'
        else
          'You have not set an emergency contact or invited a guardian yet, so '
              'SOS can sound the alarm but it has nobody to call. You can add '
              'them at any time from settings.',
        'Say "help" at any time, on any screen, to start an emergency SOS.',
      ];

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        title: "You're all set",
        body: _body,
        actions: [
          ViButton(
            label: 'Start using ImpairGency',
            icon: Icons.arrow_forward,
            onPressed: onStart,
          ),
        ],
      );
}
