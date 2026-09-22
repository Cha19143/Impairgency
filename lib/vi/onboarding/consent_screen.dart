import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../widgets/press_by_voice.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// What each switch controls, and who ends up able to see it.
class ConsentChoice {
  const ConsentChoice({
    required this.key,
    required this.title,
    required this.detail,
  });

  final String key;
  final String title;

  /// Says what it does *and who can see the result*. "Share location" without
  /// "your guardian sees where you are" is not informed consent.
  final String detail;
}

const kConsentChoices = <ConsentChoice>[
  ConsentChoice(
    key: 'location',
    title: 'Share where I am',
    detail: 'Your guardian can see your location, and an emergency SOS sends '
        'it. Nobody else ever sees it.',
  ),
  ConsentChoice(
    key: 'history',
    title: 'Remember where I have been',
    detail: 'Lets the app learn the places you go often. Kept for 60 days on '
        'this account, and you can delete it at any time.',
  ),
  ConsentChoice(
    key: 'recording',
    title: 'Record what the camera sees',
    detail: 'Saves sessions so you can review them. Only you can play them '
        'back.',
  ),
  ConsentChoice(
    key: 'activity',
    title: 'Share what the app notices',
    detail: 'Your guardian can see the last few obstacles it warned you '
        'about, the first line of anything it read to you, and where you '
        'set off for. Never the camera itself.',
  ),
  ConsentChoice(
    key: 'faces',
    title: 'Recognise people I know',
    detail: 'The scan screen names friends who agreed to be saved. Their faces '
        'stay on this phone and are never uploaded; turning this off deletes '
        'them.',
  ),
];

/// §7 requires consent for recording, location and recognition. None of the 17
/// screens in `ui.pdf` asked for any of it.
///
/// Everything starts off. Consent that is on by default is not consent, and a
/// user who is not looking at the screen cannot notice a pre-ticked box.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({
    super.key,
    required this.onContinue,
    this.initial = const {},
    this.speaker = const SilentSpeaker(),
  });

  final void Function(Map<String, bool>) onContinue;
  final Map<String, bool> initial;
  final Speaker speaker;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  late final Map<String, bool> _values = {
    for (final choice in kConsentChoices)
      choice.key: widget.initial[choice.key] ?? false,
  };

  Future<void> _toggle(ConsentChoice choice, bool value) async {
    setState(() => _values[choice.key] = value);
    // Spoken, because a switch a user cannot see gives no feedback otherwise.
    await widget.speaker.speak('${choice.title}. ${value ? 'On' : 'Off'}.');
  }

  @override
  Widget build(BuildContext context) {
    final onCount = _values.values.where((v) => v).length;

    return ViScreen(
      speaker: widget.speaker,
      step: 'Step 6 of 7',
      title: 'What may the app use?',
      body: const [
        'Everything here starts switched off. Nothing is shared until you turn '
            'it on, and you can change any of it later.',
      ],
      spokenSuffix: 'There are ${kConsentChoices.length} switches. All of them '
          'are off.',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final choice in kConsentChoices)
            _ConsentSwitch(
              choice: choice,
              value: _values[choice.key] ?? false,
              onChanged: (value) => _toggle(choice, value),
            ),
        ],
      ),
      actions: [
        ViButton(
          label: 'Continue',
          semanticLabel: onCount == 0
              ? 'Continue with everything switched off'
              : 'Continue with $onCount of ${kConsentChoices.length} switched on',
          icon: Icons.arrow_forward,
          onPressed: () => widget.onContinue(Map.of(_values)),
        ),
      ],
    );
  }
}

class _ConsentSwitch extends StatelessWidget {
  const _ConsentSwitch({
    required this.choice,
    required this.value,
    required this.onChanged,
  });

  final ConsentChoice choice;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PressByVoice(
      label: choice.title,
      onPressed: () => onChanged(!value),
      child: Semantics(
        toggled: value,
        label: '${choice.title}. ${choice.detail}',
        onTap: () => onChanged(!value),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: AppColors.navyRaised,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () => onChanged(!value),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              choice.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              choice.detail,
                              style: const TextStyle(
                                fontSize: 14.5,
                                height: 1.35,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: value,
                        onChanged: onChanged,
                        activeThumbColor: AppColors.cyan,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
