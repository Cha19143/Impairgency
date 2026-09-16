import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/profile/impairment.dart';
import '../../core/speech/speaker.dart';
import '../voice_controller.dart';
import '../widgets/dictated_field.dart';
import '../widgets/press_by_voice.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';
import '../widgets/voice_form.dart';

/// Name, age, type of impairment — and, optionally, a phone number.
///
/// The impairment is a list, not a text box. A blind user dictating a
/// diagnosis and hoping the recogniser spelt it is not a form they can fill
/// in; six large rows they can sweep through are. "Other" opens a field for
/// the person the list left out.
///
/// The phone number is not in the tester's list. It is here because the
/// guardian dashboard they also asked for has a Call button, and a Call
/// button needs a number to call. It is optional and says why it is asked.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onSave,
    this.initial,
    this.speaker = const SilentSpeaker(),
  });

  final Future<void> Function(PersonalInfo info) onSave;
  final PersonalInfo? initial;
  final Speaker speaker;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _age =
      TextEditingController(text: widget.initial?.age.toString() ?? '');
  late final _other =
      TextEditingController(text: widget.initial?.impairmentDetail ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  final _ageFocus = FocusNode();
  late ImpairmentType? _impairment = widget.initial?.impairment;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _other.dispose();
    _phone.dispose();
    _ageFocus.dispose();
    super.dispose();
  }

  Future<void> _choose(ImpairmentType type) async {
    setState(() {
      _impairment = type;
      _error = null;
    });
    final choice = kImpairmentChoices[type]!;
    // Spoken, because a row a user cannot see gives no feedback otherwise.
    await widget.speaker.speak(type == ImpairmentType.other
        ? '${choice.label}. Describe it in the field below.'
        : '${choice.label}, chosen.');
  }

  Future<void> _submit() async {
    if (_busy) return;
    final failure = validatePersonalInfo(
      name: _name.text,
      age: _age.text,
      impairment: _impairment,
      impairmentDetail: _other.text,
    );
    if (failure != null) {
      setState(() => _error = failure);
      await widget.speaker.speak(failure);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.onSave(PersonalInfo(
      name: _name.text.trim(),
      age: int.parse(_age.text.trim()),
      impairment: _impairment!,
      impairmentDetail:
          _impairment == ImpairmentType.other ? _other.text.trim() : null,
      phone: _phone.text.replaceAll(RegExp(r'[^0-9+]'), ''),
    ));
    if (mounted) setState(() => _busy = false);
  }

  InputDecoration _decoration(String label, {String? helper}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 17),
        helperText: helper,
        helperStyle: const TextStyle(fontSize: 14),
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      );

  @override
  Widget build(BuildContext context) {
    const fieldStyle = TextStyle(fontSize: 20, color: AppColors.textPrimary);

    return ViScreen(
      speaker: widget.speaker,
      step: 'Step 2 of 7',
      title: 'About you',
      body: const [
        'Your name, your age, and the kind of sight loss you have. The app '
            'uses it to speak to you by name and to choose what to warn you '
            'about first.',
      ],
      spokenSuffix: 'Three fields and a list of six choices. The last field, '
          'a phone number, is optional. Say fill in to answer them by voice, '
          'and say a choice to choose it.',
      micDetail: kFormMicDetail,
      extra: VoiceForm(
        submitLabel: 'Continue',
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DictatedField(
            label: 'Name',
            prompt: 'Say your name.',
            controller: _name,
            shape: DictationShape.name,
            enabled: !_busy,
            field: Semantics(
            textField: true,
            label: 'Your name',
            child: TextField(
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: fieldStyle,
              onSubmitted: (_) => _ageFocus.requestFocus(),
              decoration: _decoration('Your name'),
            ),
          ),
          ),
          const SizedBox(height: 14),
          DictatedField(
            label: 'Age',
            prompt: 'Say your age, in years.',
            controller: _age,
            shape: DictationShape.number,
            enabled: !_busy,
            field: Semantics(
            textField: true,
            label: 'Your age, in years',
            child: TextField(
              controller: _age,
              focusNode: _ageFocus,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              style: fieldStyle,
              decoration: _decoration('Your age'),
            ),
          ),
          ),
          const SizedBox(height: 22),
          Semantics(
            header: true,
            child: const Text(
              'Type of impairment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in kImpairmentChoices.entries)
            _ChoiceRow(
              label: entry.value.label,
              detail: entry.value.detail,
              selected: _impairment == entry.key,
              enabled: !_busy,
              onTap: () => _choose(entry.key),
            ),
          if (_impairment == ImpairmentType.other) ...[
            const SizedBox(height: 6),
            DictatedField(
              label: 'Description',
              prompt: 'Describe your impairment in your own words.',
              controller: _other,
              enabled: !_busy,
              field: Semantics(
              textField: true,
              label: 'Describe your impairment',
              child: TextField(
                controller: _other,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                style: fieldStyle,
                decoration: _decoration('Describe it in your own words'),
              ),
            ),
            ),
          ],
          const SizedBox(height: 22),
          DictatedField(
            label: 'Phone number',
            prompt: 'Say your phone number. It is optional: say cancel to '
                'leave it empty.',
            controller: _phone,
            shape: DictationShape.phone,
            enabled: !_busy,
            field: Semantics(
            textField: true,
            label: 'Your phone number, optional. A guardian can call it.',
            child: TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              style: fieldStyle,
              onSubmitted: (_) => _submit(),
              decoration: _decoration(
                'Your phone number (optional)',
                helper: 'So a guardian can call you from their app.',
              ),
            ),
          ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: const TextStyle(
                    fontSize: 16, height: 1.35, color: AppColors.amber),
              ),
            ),
          ],
        ],
      ),
      ),
      actions: [
        ViButton(
          label: _busy ? 'Saving…' : 'Continue',
          icon: Icons.arrow_forward,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

/// One choice in the list. Selection is shown by a tick *and* a border, and
/// announced as "selected" — never by colour alone.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.detail,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressByVoice(
        // The choice's name alone: "blind", not the sentence under it.
        label: label,
        onPressed: enabled ? onTap : null,
        child: Semantics(
          button: true,
          selected: selected,
          enabled: enabled,
          label: '$label. $detail',
          onTap: enabled ? onTap : null,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: selected ? AppColors.navyRaised : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: enabled ? onTap : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: kMinTargetSize),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? AppColors.cyan : AppColors.hairline,
                        width: selected ? 3 : 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 30,
                          color: selected
                              ? AppColors.cyan
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                detail,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.3,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
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
