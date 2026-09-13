import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/pairing/pairing_code.dart';

/// Redeems a code, or explains why it could not.
typedef RedeemHandler = Future<String?> Function(String code);

/// The guardian app's front door.
///
/// The submitted design has a Guardian Dashboard on page 17 and no screen
/// anywhere that connects a guardian to a user. This is that screen, and
/// without it the second app is unreachable.
///
/// Its user is usually sighted, so it is not built under the same constraints
/// as the visually impaired app - but the code they are typing was read to them
/// out loud, and everything here follows from that.
class AcceptInvitationScreen extends StatefulWidget {
  const AcceptInvitationScreen({
    super.key,
    required this.onRedeem,
    this.onAccepted,
    this.onBack,
  });

  /// Back to wherever the guardian came from. Without it this screen had no
  /// way out but a valid code: the system back gesture left the app.
  final VoidCallback? onBack;

  /// Returns null on success, or a message to show on failure.
  final RedeemHandler onRedeem;

  final VoidCallback? onAccepted;

  @override
  State<AcceptInvitationScreen> createState() => _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState extends State<AcceptInvitationScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Clear the error the moment they start correcting it. Leaving a stale
      // "that code has expired" under a field they are already fixing reads as
      // a second failure.
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit => isValidPairingCode(_controller.text) && !_busy;

  Future<void> _submit() async {
    if (!_canSubmit) {
      setState(() => _error =
          pairingRejectionMessage(PairingCodeRejection.malformed));
      return;
    }
    setState(() => _busy = true);
    final failure = await widget.onRedeem(normalisePairingCode(_controller.text));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
    });
    if (failure == null) widget.onAccepted?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ImpairGency'),
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: widget.onBack,
              ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Enter the code they gave you',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Eight characters, read aloud from their phone. '
                'It does not contain the letter O or the number zero.',
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Semantics(
                textField: true,
                label: 'Invitation code, eight characters',
                child: TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: kPairingCodeLength + 1, // room for a typed space
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                inputFormatters: [
                  // Only the characters that can actually be in a code. Typing
                  // an O and being told later that it is invalid is a worse
                  // experience than the key doing nothing.
                  FilteringTextInputFormatter.allow(
                    RegExp('[${kSpeakSafeAlphabet.toLowerCase()}'
                        '$kSpeakSafeAlphabet ]'),
                  ),
                  UpperCaseFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: 'Invitation code',
                  counterText: '',
                  errorText: _error,
                  errorMaxLines: 4,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : const Text('ACCEPT INVITATION'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Codes work once and expire after thirty minutes. '
                'If yours has run out, ask them to make a new one.',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uppercases as the guardian types, so the field always shows the code the
/// way it was read to them.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
