import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/voice/voice_commands.dart';
import '../voice_controller.dart';
import 'dictated_field.dart';
import 'voice_access.dart';

/// What the microphone on a screen with a form says it can do.
const String kFormMicDetail = "Say fill in, or a button's name";

/// The fields below it, answered in turn when the user says "fill in".
///
/// Asks for each empty [DictatedField] in the order they are on screen - or,
/// when none is empty, for every one of them again - then names [submitLabel],
/// so the last thing said is how to send what was filled in. Stops at the
/// first field left unanswered, rather than asking an empty room for the rest.
class VoiceForm extends StatefulWidget {
  const VoiceForm({super.key, required this.child, this.submitLabel});

  final Widget child;

  /// The button that sends the form.
  final String? submitLabel;

  static VoiceFormState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<VoiceFormState>();

  @override
  State<VoiceForm> createState() => VoiceFormState();
}

class VoiceFormState extends State<VoiceForm> {
  final List<DictatedFieldState> _fields = [];
  VoiceController? _voice;
  VoiceScopeHandle? _scope;
  bool _filling = false;

  void add(DictatedFieldState field) => _fields.add(field);
  void remove(DictatedFieldState field) => _fields.remove(field);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final voice = VoiceAccess.maybeOf(context);
    if (voice == _voice) return;
    _scope?.detach();
    _voice = voice;
    _scope = voice?.attach(VoiceScope(onCommand: _onCommand));
  }

  @override
  void dispose() {
    _scope?.detach();
    super.dispose();
  }

  Future<bool> _onCommand(ParsedCommand command) async {
    if (command.command != VoiceCommand.fillIn) return false;
    await fillIn();
    return true;
  }

  /// Asks for the fields in turn.
  Future<void> fillIn() async {
    final voice = _voice;
    if (voice == null || _filling) return;
    _filling = true;
    try {
      final fields = [
        for (final field in _fields)
          if (field.mounted && field.canDictate) field,
      ];
      if (fields.isEmpty) {
        await voice.speaker.speak('There is nothing to fill in right now.');
        return;
      }
      final empty = [
        for (final field in fields)
          if (field.isEmpty) field,
      ];
      for (final field in empty.isEmpty ? fields : empty) {
        final kept = await field.dictate();
        if (!mounted) return;
        if (kept == null) {
          await voice.speaker.speak('Say fill in to carry on.');
          return;
        }
      }
      final submit = widget.submitLabel;
      if (submit != null) {
        await voice.speaker.speak('Say $submit when you are ready.');
      }
    } finally {
      _filling = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
