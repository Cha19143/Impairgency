import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Moved ahead of the device screens.
///
/// In `ui.pdf` this was step 4 of 5, behind two screens of pairing for hardware
/// that does not exist. The optional thing was standing in front of the thing
/// that could save someone's life.
///
/// Still skippable — but skipping now says what it costs, out loud. `cprwire`
/// had a "Skip for Now" that passed silently, which is how a user ends up with
/// an SOS button that has nobody to call and no idea that is the case.
class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({
    super.key,
    required this.onSave,
    required this.onSkip,
    this.speaker = const SilentSpeaker(),
  });

  final void Function(String name, String number) onSave;
  final VoidCallback onSkip;
  final Speaker speaker;

  @override
  State<EmergencyContactScreen> createState() => _EmergencyContactScreenState();
}

class _EmergencyContactScreenState extends State<EmergencyContactScreen> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _numberFocus = FocusNode();
  String? _error;
  bool _confirmingSkip = false;

  static const String skipWarning =
      'Without a contact, an emergency SOS can sound the alarm and share where '
      'you are, but it will have nobody to call. You can add one later from '
      'settings.';

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final number = _number.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (name.isEmpty) {
      _fail('Enter the name of the person to call.');
      return;
    }
    if (number.length < 7) {
      _fail('That does not look like a phone number.');
      return;
    }
    widget.onSave(name, number);
  }

  void _fail(String message) {
    setState(() => _error = message);
    widget.speaker.speak(message);
  }

  Future<void> _skip() async {
    if (!_confirmingSkip) {
      // Said before it is done, not after. A warning that arrives once the
      // decision is made is not a warning.
      setState(() => _confirmingSkip = true);
      await widget.speaker.speak(skipWarning);
      return;
    }
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    return ViScreen(
      speaker: widget.speaker,
      step: 'Step 3 of 6',
      title: 'Who should we call in an emergency?',
      body: const [
        'One person the app will ring when you say "help" or press the SOS '
            'button.',
      ],
      spokenSuffix: 'Enter their name and number, or skip this step.',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 20, color: AppColors.textPrimary),
            onSubmitted: (_) => _numberFocus.requestFocus(),
            decoration: const InputDecoration(
              labelText: 'Their name',
              labelStyle: TextStyle(fontSize: 17),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _number,
            focusNode: _numberFocus,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 20, color: AppColors.textPrimary),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Their phone number',
              labelStyle: const TextStyle(fontSize: 17),
              errorText: _error,
              errorMaxLines: 3,
              errorStyle: const TextStyle(fontSize: 15),
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            ),
          ),
          if (_confirmingSkip) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                skipWarning,
                style: TextStyle(
                    fontSize: 16, height: 1.4, color: AppColors.amber),
              ),
            ),
          ],
        ],
      ),
      actions: [
        ViButton(
          label: 'Save this contact',
          icon: Icons.check,
          onPressed: _save,
        ),
        ViButton(
          label: _confirmingSkip ? 'Skip anyway' : 'Skip for now',
          semanticLabel: _confirmingSkip
              ? 'Skip anyway. SOS will have nobody to call.'
              : 'Skip for now. This will explain what SOS cannot do without a '
                  'contact.',
          kind: ViButtonKind.quiet,
          onPressed: _skip,
        ),
      ],
    );
  }
}
