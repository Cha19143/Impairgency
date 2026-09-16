import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/auth/email_address.dart';
import '../../core/speech/speaker.dart';
import '../voice_controller.dart';
import '../widgets/dictated_field.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';
import '../widgets/voice_form.dart';

/// Returns null on success, or a sentence to say and show.
typedef CreateAccountHandler = Future<String?> Function(
    String email, String password);

/// Moved from step 5 of 5 to step 1 of 6. That move is the whole rework.
///
/// `ui.pdf` collected a vision category, two screens of device pairing and an
/// emergency contact *before* asking for an account — four screens of answers
/// with nowhere to be stored, and a login screen at the very start for an
/// account that did not exist yet.
///
/// **A password is never dictated.** `ui.pdf` p.7 offered to "speak the
/// details instead of typing"; a password said out loud is not a password. The
/// email address can be said - it is read back letter by letter and kept only
/// on a yes, because a dictated address is wrong often enough that nobody
/// should have to find out from an email that never arrives.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    super.key,
    required this.onCreate,
    this.speaker = const SilentSpeaker(),
  });

  final CreateAccountHandler onCreate;
  final Speaker speaker;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;

    final problem = emailAddressProblem(email);
    if (problem != null) {
      await _fail(problem);
      return;
    }
    if (password.length < 8) {
      await _fail('Your password needs at least eight characters.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onCreate(email, password);
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) await _fail(failure);
  }

  Future<void> _fail(String message) async {
    if (!mounted) return;
    setState(() => _error = message);
    // Said, not only shown. An error a blind user cannot hear is not an error
    // message, it is a dead end.
    await widget.speaker.speak(message);
  }

  @override
  Widget build(BuildContext context) {
    return ViScreen(
      speaker: widget.speaker,
      step: 'Step 1 of 7',
      title: 'Create your account',
      body: const [
        'Your email and a password of at least eight characters.',
      ],
      spokenSuffix: 'Say fill in to say your email address. Type the password '
          'with the keyboard: a password said out loud is not a password.',
      micDetail: kFormMicDetail,
      extra: VoiceForm(
        submitLabel: 'Create account',
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DictatedField(
            label: 'Email address',
            controller: _email,
            shape: DictationShape.email,
            enabled: !_busy,
            field: Semantics(
            textField: true,
            label: 'Email address',
            child: TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 20, color: AppColors.textPrimary),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: const InputDecoration(
              labelText: 'Email address',
              labelStyle: TextStyle(fontSize: 17),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            ),
          ),
          ),
          ),
          const SizedBox(height: 14),
          Semantics(
            textField: true,
            label: 'Password, at least eight characters',
            child: TextField(
            controller: _password,
            focusNode: _passwordFocus,
            enabled: !_busy,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            style: const TextStyle(fontSize: 20, color: AppColors.textPrimary),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              labelStyle: const TextStyle(fontSize: 17),
              helperText: 'At least eight characters',
              helperStyle: const TextStyle(fontSize: 14),
              errorText: _error,
              errorMaxLines: 4,
              errorStyle: const TextStyle(fontSize: 15),
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            ),
          ),
          ),
        ],
      ),
      ),
      actions: [
        ViButton(
          label: _busy ? 'Creating your account…' : 'Create account',
          icon: Icons.arrow_forward,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
