import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Returns null when the link is on its way, or a sentence to say and show.
typedef ResetHandler = Future<String?> Function(String email);

/// The way back in for someone who has forgotten the way back in.
///
/// Firebase Auth's own reset email, the same mechanism as the verification
/// mail: no codes stored anywhere, nothing for a server to do. The screen
/// says the same thing whether or not the address has an account, because
/// telling a stranger which emails are registered is a leak, and the person
/// it belongs to gets the mail either way.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.onSendReset,
    required this.onBack,
    this.initialEmail,
    this.speaker = const SilentSpeaker(),
  });

  final ResetHandler onSendReset;

  /// Back to sign-in, which is where the new password is used.
  final VoidCallback onBack;

  /// Carried over from the sign-in form, so it is not typed twice.
  final String? initialEmail;

  final Speaker speaker;

  /// Said and shown once the mail has gone.
  static String sentMessage(String email) =>
      'If there is an account for $email, a link to choose a new password '
      'is on its way. Open the email, choose a password, then come back and '
      'sign in.';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  String? _error;
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!email.contains('@') || email.length < 5) {
      await _fail('That does not look like an email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onSendReset(email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      await _fail(failure);
      return;
    }
    setState(() => _sent = true);
    await widget.speaker.speak(ForgotPasswordScreen.sentMessage(email));
  }

  Future<void> _fail(String message) async {
    if (!mounted) return;
    setState(() => _error = message);
    await widget.speaker.speak(message);
  }

  @override
  Widget build(BuildContext context) {
    return ViScreen(
      speaker: widget.speaker,
      title: 'Forgot your password?',
      body: const [
        'Type the email you signed up with. We will send a link to choose a '
            'new password.',
      ],
      spokenSuffix: 'One field, and a button to send the link.',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            textField: true,
            label: 'Email address',
            child: TextField(
              controller: _email,
              enabled: !_busy && !_sent,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.username],
              style:
                  const TextStyle(fontSize: 20, color: AppColors.textPrimary),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Email address',
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
          if (_sent) ...[
            const SizedBox(height: 18),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  ForgotPasswordScreen.sentMessage(_email.text.trim()),
                  style: const TextStyle(
                      fontSize: 16, height: 1.4, color: AppColors.green),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!_sent)
          ViButton(
            label: _busy ? 'Sending…' : 'Send me the link',
            icon: Icons.mail_outline,
            onPressed: _busy ? null : _submit,
          ),
        ViButton(
          label: _sent ? 'Back to sign in' : 'Back',
          icon: _sent ? Icons.arrow_forward : null,
          kind: _sent ? ViButtonKind.primary : ViButtonKind.quiet,
          onPressed: widget.onBack,
        ),
      ],
    );
  }
}
