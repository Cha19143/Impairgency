import 'package:flutter/material.dart';

import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Where everything skippable during onboarding can be done later.
///
/// The requirements document asks for device connection "during registration or
/// through the application's homepage/settings" (§5). `ui.pdf` only offered it
/// during registration, so a user who skipped it could never come back — and
/// the same was true of the emergency contact and the guardian invite.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onConsent,
    required this.onLearned,
    required this.onDevice,
    required this.onEmergencyContact,
    required this.onInviteGuardian,
    required this.onSafetyNotice,
    required this.onSignOut,
    required this.onBack,
    this.hasContact = false,
    this.hasGuardian = false,
    this.speaker = const SilentSpeaker(),
  });

  final VoidCallback onConsent;
  final VoidCallback onLearned;
  final VoidCallback onDevice;
  final VoidCallback onEmergencyContact;
  final VoidCallback onInviteGuardian;
  final VoidCallback onSafetyNotice;

  /// Opens the confirmation, not the sign-out itself.
  final VoidCallback onSignOut;

  final VoidCallback onBack;
  final bool hasContact;
  final bool hasGuardian;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        title: 'Settings',
        body: const [],
        actions: [
          ViButton(
            label: 'Emergency contact',
            detail: hasContact
                ? 'Change who is called in an emergency'
                : 'Not set. SOS has nobody to call.',
            icon: Icons.phone_outlined,
            kind: hasContact ? ViButtonKind.secondary : ViButtonKind.emergency,
            onPressed: onEmergencyContact,
          ),
          ViButton(
            label: 'Guardian',
            detail: hasGuardian
                ? 'Invite another guardian'
                : 'Nobody is watching over you yet',
            icon: Icons.people_outline,
            kind: ViButtonKind.secondary,
            onPressed: onInviteGuardian,
          ),
          ViButton(
            label: 'What the app is using',
            detail: 'Location, history, recording, faces',
            icon: Icons.lock_outline,
            kind: ViButtonKind.secondary,
            onPressed: onConsent,
          ),
          ViButton(
            label: 'What the app has learned',
            detail: 'See it, and delete any of it',
            icon: Icons.psychology_outlined,
            kind: ViButtonKind.secondary,
            onPressed: onLearned,
          ),
          ViButton(
            label: 'Connect a device',
            detail: 'Optional. Everything works without one.',
            icon: Icons.watch_outlined,
            kind: ViButtonKind.secondary,
            onPressed: onDevice,
          ),
          ViButton(
            label: 'What this app can and cannot do',
            kind: ViButtonKind.quiet,
            onPressed: onSafetyNotice,
          ),
          // Last, and quiet, and it asks before it does anything. Until this
          // existed there was no way off an account on a phone that had one -
          // which also meant the sign-in screen was unreachable for anybody
          // who had ever signed in.
          ViButton(
            label: 'Sign out',
            detail: 'This phone forgets your account',
            kind: ViButtonKind.quiet,
            onPressed: onSignOut,
          ),
          ViButton(
            label: 'Back',
            kind: ViButtonKind.quiet,
            onPressed: onBack,
          ),
        ],
      );
}
