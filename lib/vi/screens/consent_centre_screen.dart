import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../onboarding/consent_screen.dart';
import '../widgets/press_by_voice.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Inspect and revoke, in one place.
///
/// Uses the same [kConsentChoices] as onboarding, so what was agreed to and
/// what can be revoked are described in identical words.
///
/// Revocation is enforced by the security rules, not by this screen. Turning
/// `history` off stops the server accepting new fixes; turning `location` off
/// stops a guardian reading them. A consent screen that only hides a button is
/// not consent.
class ConsentCentreScreen extends StatefulWidget {
  const ConsentCentreScreen({
    super.key,
    required this.current,
    required this.onSave,
    required this.onBack,
    this.speaker = const SilentSpeaker(),
  });

  final Map<String, bool> current;
  final Future<void> Function(Map<String, bool>) onSave;
  final VoidCallback onBack;
  final Speaker speaker;

  @override
  State<ConsentCentreScreen> createState() => _ConsentCentreScreenState();
}

class _ConsentCentreScreenState extends State<ConsentCentreScreen> {
  late final Map<String, bool> _values = {
    for (final c in kConsentChoices) c.key: widget.current[c.key] ?? false,
  };
  bool _saving = false;

  Future<void> _set(String key, bool value) async {
    setState(() => _values[key] = value);
    final choice = kConsentChoices.firstWhere((c) => c.key == key);
    await widget.speaker.speak('${choice.title}. ${value ? 'On' : 'Off'}.');
  }

  Future<void> _turnAllOff() async {
    setState(() {
      for (final key in _values.keys) {
        _values[key] = false;
      }
    });
    await widget.speaker.speak('Everything is off.');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave(Map.of(_values));
    if (!mounted) return;
    setState(() => _saving = false);
    await widget.speaker.speak('Saved.');
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final anyOn = _values.values.any((v) => v);

    return ViScreen(
      speaker: widget.speaker,
      title: 'What the app is using',
      body: [
        anyOn
            ? 'Turn anything off and it stops immediately, on the server as '
                'well as on this phone.'
            : 'Nothing is switched on. Nothing about you is being shared.',
      ],
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final choice in kConsentChoices)
            PressByVoice(
              label: choice.title,
              onPressed: () => _set(choice.key, !(_values[choice.key] ?? false)),
              child: Semantics(
                toggled: _values[choice.key] ?? false,
                label: '${choice.title}. ${choice.detail}',
                onTap: () => _set(choice.key, !(_values[choice.key] ?? false)),
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: AppColors.navyRaised,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () =>
                            _set(choice.key, !(_values[choice.key] ?? false)),
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
                                    Text(choice.title,
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary)),
                                    const SizedBox(height: 4),
                                    Text(choice.detail,
                                        style: const TextStyle(
                                            fontSize: 14.5,
                                            height: 1.35,
                                            color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _values[choice.key] ?? false,
                                activeThumbColor: AppColors.cyan,
                                onChanged: (v) => _set(choice.key, v),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (anyOn)
          ViButton(
            label: 'Turn everything off',
            icon: Icons.lock_outline,
            kind: ViButtonKind.emergency,
            onPressed: _turnAllOff,
          ),
        ViButton(
          label: _saving ? 'Saving…' : 'Save',
          icon: Icons.check,
          onPressed: _saving ? null : _save,
        ),
        ViButton(
          label: 'Back without saving',
          kind: ViButtonKind.quiet,
          onPressed: widget.onBack,
        ),
      ],
    );
  }
}
