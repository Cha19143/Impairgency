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
    this.onSavedPlaces,
    this.onPeople,
    this.contactCount = 0,
    this.hasGuardian = false,
    this.speaker = const SilentSpeaker(),
    this.handsFree = false,
    this.onToggleHandsFree,
  });

  final VoidCallback onConsent;
  final VoidCallback onLearned;
  final VoidCallback onDevice;
  final VoidCallback onEmergencyContact;
  final VoidCallback onInviteGuardian;
  final VoidCallback onSafetyNotice;

  /// Opens the confirmation, not the sign-out itself.
  final VoidCallback onSignOut;

  /// Home, work, school and the rest. Null hides the entry.
  final VoidCallback? onSavedPlaces;

  /// The friends whose faces this phone knows. Null hides the entry.
  final VoidCallback? onPeople;

  /// Whether voice commands are listened for without a tap.
  final bool handsFree;

  /// Null hides the entry.
  final VoidCallback? onToggleHandsFree;

  final VoidCallback onBack;

  /// How many people SOS rings. Zero is flagged, not hidden.
  final int contactCount;
  final bool hasGuardian;
  bool get hasContact => contactCount > 0;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        title: 'Settings',
        body: const [],
        actions: [
          ViButton(
            label: 'Emergency contacts',
            detail: hasContact
                ? '$contactCount ${contactCount == 1 ? 'person' : 'people'} '
                    'called in an emergency. Change who, or the order.'
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
          if (onSavedPlaces != null)
            ViButton(
              label: 'Saved places',
              detail: 'Home, work, school - the buttons in Smart assistance',
              icon: Icons.edit_location_alt_outlined,
              kind: ViButtonKind.secondary,
              onPressed: onSavedPlaces,
            ),
          if (onPeople != null)
            ViButton(
              label: 'People I know',
              detail: 'Friends the scan screen names. Kept on this phone only.',
              icon: Icons.face_outlined,
              kind: ViButtonKind.secondary,
              onPressed: onPeople,
            ),
          if (onToggleHandsFree != null)
            ViButton(
              // The state is not in the label. "Hands-free voice: on" as a
              // button's name made "turn on hands-free" press it - and turn
              // it off.
              label: 'Hands-free voice',
              detail: handsFree
                  ? 'On: listens without a tap on every screen, for commands '
                      "and buttons' names. Tap to turn it off."
                  : 'Off: tap to speak before each command. Tap to turn '
                      'hands-free on.',
              icon: handsFree ? Icons.mic : Icons.mic_off_outlined,
              kind: ViButtonKind.secondary,
              onPressed: onToggleHandsFree,
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
