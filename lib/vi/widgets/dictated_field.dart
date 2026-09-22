import 'package:flutter/material.dart';

import '../voice_controller.dart';
import 'vi_button.dart';
import 'voice_access.dart';
import 'voice_form.dart';

/// A text field that can also be answered by voice.
///
/// Draws [field] as the screen built it, and under it a "Say the …" button
/// that asks for the answer, reads back what was heard, and fills the field in
/// only once the user says yes. The button is itself pressed by saying its
/// label, so "say the phone number" works from anywhere on the screen, and a
/// [VoiceForm] above it asks for each field in turn on "fill in".
///
/// Never for a password. A password field is not wrapped in one of these: a
/// password said out loud is not a password.
class DictatedField extends StatefulWidget {
  const DictatedField({
    super.key,
    required this.label,
    required this.controller,
    required this.field,
    this.shape = DictationShape.words,
    this.prompt,
    this.enabled = true,
    this.onDictated,
    this.inForm = true,
  });

  /// What the field is, as it is said: "Email address".
  final String label;

  final TextEditingController controller;

  /// The text field itself.
  final Widget field;

  final DictationShape shape;

  /// What is said to ask for it. "Say the <label>." by default.
  final String? prompt;

  final bool enabled;

  /// Called with what was kept, once it is in the field.
  final ValueChanged<String>? onDictated;

  /// Whether a [VoiceForm] above asks for this field on "fill in". A search
  /// box is not part of the form around it: it does something at once.
  final bool inForm;

  @override
  State<DictatedField> createState() => DictatedFieldState();
}

class DictatedFieldState extends State<DictatedField> {
  VoiceController? _voice;
  VoiceFormState? _form;
  bool _listening = false;

  /// Whether this field can be answered by voice right now.
  bool get canDictate => _voice != null && widget.enabled;

  bool get isEmpty => widget.controller.text.trim().isEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voice = VoiceAccess.maybeOf(context);
    final form = widget.inForm ? VoiceForm.maybeOf(context) : null;
    if (form != _form) {
      _form?.remove(this);
      _form = form?..add(this);
    }
  }

  @override
  void dispose() {
    _form?.remove(this);
    super.dispose();
  }

  /// Asks for this field by voice. Returns what was kept, or null.
  Future<String?> dictate() async {
    final voice = _voice;
    if (voice == null || !widget.enabled || _listening) return null;
    setState(() => _listening = true);
    try {
      final value = await voice.dictate(
        label: widget.label,
        shape: widget.shape,
        prompt: widget.prompt,
      );
      if (value != null && mounted) {
        widget.controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
        widget.onDictated?.call(value);
      }
      return value;
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_voice == null) return widget.field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.field,
        const SizedBox(height: 6),
        ViButton(
          label: 'Say the ${widget.label.toLowerCase()}',
          detail: _listening ? 'Listening for it now' : null,
          icon: Icons.mic_none_outlined,
          kind: ViButtonKind.quiet,
          onPressed: widget.enabled && !_listening ? () => dictate() : null,
        ),
      ],
    );
  }
}
