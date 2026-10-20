import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/pairing/pairing_code.dart';
import '../../core/speech/speaker.dart';
import '../../vi/widgets/vi_button.dart';
import '../../vi/widgets/vi_screen.dart';
import '../guardian_registration.dart';
import 'accept_invitation_screen.dart' show UpperCaseFormatter;

/// Returns null once the account exists and is linked, or why not.
typedef GuardianRegisterHandler = Future<RegisterFailure?> Function(
    GuardianRegistration registration);

/// The guardian's own registration: name, email, password, phone, and the
/// code that links them to the person they watch over.
///
/// The code is checked twice. Its shape is checked here, before anything is
/// sent, so a mistyped character is caught while the field still has focus.
/// Whether it exists, has been used, or has expired can only be known once
/// there is an account to ask with - the rules require a signed-in reader -
/// so that answer comes back from [onRegister], in the pairing code's own
/// words. The account that was just made stays signed in, the fields that
/// made it are locked, and the button asks only for the code again.
///
/// Success leaves the screen through [onRegistered]. The redirect cannot do
/// it: a signed-in guardian is allowed to stay on this page, so the one that
/// fixes a refused code is not thrown out mid-form - and that same rule is
/// why the tester's successful registration "did nothing".
///
/// Its user is usually sighted, so it is denser than the visually impaired
/// app's screens - but it is still built on the same parts and still speaks
/// its errors, because "usually" is not "always".
class GuardianRegisterScreen extends StatefulWidget {
  const GuardianRegisterScreen({
    super.key,
    required this.onRegister,
    required this.onRegistered,
    required this.onSignIn,
    this.speaker = const SilentSpeaker(),
  });

  final GuardianRegisterHandler onRegister;

  /// The account exists and is linked: open the guardian's dashboard.
  final VoidCallback onRegistered;

  /// For a guardian who already has an account.
  final VoidCallback onSignIn;

  final Speaker speaker;

  @override
  State<GuardianRegisterScreen> createState() => _GuardianRegisterScreenState();
}

class _GuardianRegisterScreenState extends State<GuardianRegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _focus = {for (final f in _Field.values) f: FocusNode()};
  String? _error;
  _Field? _errorField;
  bool _busy = false;

  /// Signed in, account written, only the code left.
  bool _accountReady = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _phone, _code]) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final failure = validateGuardianRegistration(
      name: _name.text,
      email: _email.text,
      password: _password.text,
      phone: _phone.text,
      pairingCode: _code.text,
    );
    if (failure != null) {
      await _fail(failure, _fieldFor(failure));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _errorField = null;
    });
    RegisterFailure? result;
    try {
      result = await widget.onRegister(GuardianRegistration(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        phone: normalisePhone(_phone.text),
        pairingCode: normalisePairingCode(_code.text),
      ));
    } catch (_) {
      result = const RegisterFailure(
          'Something went wrong. Check your connection and try again.');
    } finally {
      // Whatever happened, the button comes back. A button stuck on
      // "Creating your account…" is a screen that has stopped answering.
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (result == null) {
      widget.onRegistered();
      return;
    }
    if (result.accountReady && !_accountReady) {
      setState(() => _accountReady = true);
    }
    await _fail(result.message, _fieldForRefusal(result.field));
  }

  _Field _fieldForRefusal(RegisterField field) => switch (field) {
        RegisterField.name => _Field.name,
        RegisterField.email => _Field.email,
        RegisterField.password => _Field.password,
        RegisterField.phone => _Field.phone,
        // A general failure is shown by the button, where the eye already is.
        RegisterField.code || RegisterField.general => _Field.code,
      };

  /// Which field a validation sentence is about, so the error sits under it.
  _Field _fieldFor(String failure) {
    if (failure.contains('name')) return _Field.name;
    if (failure.contains('email')) return _Field.email;
    if (failure.contains('password')) return _Field.password;
    if (failure.contains('phone')) return _Field.phone;
    return _Field.code;
  }

  Future<void> _fail(String message, _Field field) async {
    if (!mounted) return;
    setState(() {
      _error = message;
      _errorField = field;
    });
    _focus[field]!.requestFocus();
    await widget.speaker.speak(message);
  }

  Widget _field(
    _Field field, {
    required TextEditingController controller,
    required String label,
    String? helper,
    TextInputType? keyboardType,
    bool obscure = false,
    Iterable<String>? autofill,
    List<TextInputFormatter>? formatters,
    TextCapitalization capitalization = TextCapitalization.none,
    bool last = false,
    TextStyle? style,
    int? maxLength,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Semantics(
          textField: true,
          label: helper == null ? label : '$label. $helper',
          child: TextField(
            controller: controller,
            focusNode: _focus[field],
            // Once the account exists, only the code can still be changed.
            enabled: !_busy && (!_accountReady || field == _Field.code),
            keyboardType: keyboardType,
            obscureText: obscure,
            autocorrect: !obscure && keyboardType != TextInputType.emailAddress,
            autofillHints: autofill,
            inputFormatters: formatters,
            textCapitalization: capitalization,
            maxLength: maxLength,
            textInputAction:
                last ? TextInputAction.done : TextInputAction.next,
            style: style ??
                const TextStyle(fontSize: 20, color: AppColors.textPrimary),
            onSubmitted: (_) => last
                ? _submit()
                : _focus[_Field.values[field.index + 1]]!.requestFocus(),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontSize: 17),
              helperText: helper,
              helperStyle: const TextStyle(fontSize: 14),
              helperMaxLines: 3,
              counterText: '',
              errorText: _errorField == field ? _error : null,
              errorMaxLines: 4,
              errorStyle: const TextStyle(fontSize: 15),
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ViScreen(
      // A guardian can see the form; the app's microphone is for the person
      // they watch over.
      mic: false,
      speaker: widget.speaker,
      title: 'Create a guardian account',
      body: const [
        'You will be told when the person you watch over calls for help, and '
            'where they are - if they choose to share it.',
      ],
      spokenSuffix: 'Five fields: name, email, password, phone number, and '
          'the eight-character code read out from their phone. '
          'Create account. I already have an account.',
      extra: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              _Field.name,
              controller: _name,
              label: 'Your name',
              capitalization: TextCapitalization.words,
              autofill: const [AutofillHints.name],
            ),
            _field(
              _Field.email,
              controller: _email,
              label: 'Email address',
              keyboardType: TextInputType.emailAddress,
              autofill: const [AutofillHints.email],
            ),
            _field(
              _Field.password,
              controller: _password,
              label: 'Password',
              helper: 'At least eight characters',
              obscure: true,
              autofill: const [AutofillHints.newPassword],
            ),
            _field(
              _Field.phone,
              controller: _phone,
              label: 'Your phone number',
              helper: 'So the person you watch over can call you back.',
              keyboardType: TextInputType.phone,
              autofill: const [AutofillHints.telephoneNumber],
            ),
            _field(
              _Field.code,
              controller: _code,
              label: 'Their invitation code',
              helper: _accountReady
                  ? 'Your account is made. Only the code is left.'
                  : 'Eight characters, read aloud from their phone. It has '
                      'no letter O and no zero.',
              capitalization: TextCapitalization.characters,
              maxLength: kPairingCodeLength + 1,
              last: true,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              formatters: [
                FilteringTextInputFormatter.allow(
                  RegExp('[${kSpeakSafeAlphabet.toLowerCase()}'
                      '$kSpeakSafeAlphabet ]'),
                ),
                UpperCaseFormatter(),
              ],
            ),
          ],
        ),
      ),
      actions: [
        ViButton(
          label: _busy
              ? (_accountReady ? 'Linking…' : 'Creating your account…')
              : (_accountReady ? 'Link with this code' : 'Create account'),
          icon: Icons.arrow_forward,
          onPressed: _busy ? null : _submit,
        ),
        if (!_accountReady)
          ViButton(
            label: 'I already have an account',
            kind: ViButtonKind.quiet,
            onPressed: _busy ? null : widget.onSignIn,
          ),
      ],
    );
  }
}

enum _Field { name, email, password, phone, code }
