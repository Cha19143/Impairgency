import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Returns null on success, or a sentence to say and show.
typedef SignInHandler = Future<String?> Function(String email, String password);

/// The door back in, for an account that already exists.
///
/// The welcome screen has offered "Sign in" since the rework, and until now the
/// button led to *Create your account*. A returning user typed the email they
/// already had, and Firebase told them there was already an account with that
/// email and to try signing in instead — which is what they had just tried to
/// do. Two buttons, one destination, and the only way out was to reinstall.
///
/// Deliberately unlike [CreateAccountScreen] in one respect: the password is
/// not length-checked here. Eight characters is the rule for a password being
/// *chosen*; applying it to one being *typed back* would refuse a working
/// password on the client and blame the user for it.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.onSignIn,
    required this.onCreateAccount,
    this.onForgotPassword,
    this.speaker = const SilentSpeaker(),
  });

  final SignInHandler onSignIn;

  /// Opens the reset flow, carrying whatever email has been typed so far.
  final void Function(String email)? onForgotPassword;

  /// For someone who arrived here without an account. Without it this screen
  /// is the dead end it was written to fix, pointing the other way.
  final VoidCallback onCreateAccount;

  final Speaker speaker;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
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

    if (!email.contains('@') || email.length < 5) {
      await _fail('That does not look like an email address.');
      return;
    }
    if (password.isEmpty) {
      await _fail('Type your password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onSignIn(email, password);
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
      title: 'Sign in',
      body: const [
        'The email and password you already use for ImpairGency.',
      ],
      spokenSuffix: 'Use the keyboard to type them. If you do not have an '
          'account yet, there is a button to create one.',
      extra: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              textField: true,
              label: 'Email address',
              child: TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                style:
                    const TextStyle(fontSize: 20, color: AppColors.textPrimary),
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
            const SizedBox(height: 14),
            Semantics(
              textField: true,
              label: 'Password',
              child: TextField(
                controller: _password,
                focusNode: _passwordFocus,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                style:
                    const TextStyle(fontSize: 20, color: AppColors.textPrimary),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(fontSize: 17),
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
          label: _busy ? 'Signing you in…' : 'Sign in',
          icon: Icons.arrow_forward,
          onPressed: _busy ? null : _submit,
        ),
        ViButton(
          label: 'Create an account instead',
          detail: 'If you have not made one yet',
          icon: Icons.person_add_alt_1,
          kind: ViButtonKind.secondary,
          onPressed: _busy ? null : widget.onCreateAccount,
        ),
        if (widget.onForgotPassword != null)
          ViButton(
            label: 'Forgot your password?',
            kind: ViButtonKind.quiet,
            onPressed: _busy
                ? null
                : () => widget.onForgotPassword!(_email.text.trim()),
          ),
      ],
    );
  }
}
