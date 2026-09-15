import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../../data/auth_service.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// "Check your email": where a new account waits until its address is real.
///
/// The tester typed a made-up email into Create account and was let straight
/// in. The verification link was always sent; nothing ever asked whether it
/// had been opened. This asks.
///
/// Both apps land here - a guardian after their code is linked, a visually
/// impaired user after the account step - and leave the same way: the link
/// is opened, the app is told, and the router moves on. Returning from the
/// mail app checks by itself (see `AppSession.setForeground`), so the button
/// is for anyone who stayed.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.onCheck,
    required this.onResend,
    required this.onUseDifferentEmail,
    this.linkSent = true,
    this.speaker = const SilentSpeaker(),
    this.now = DateTime.now,
  });

  /// The address the link went to, or null if the account has none on hand.
  final String? email;

  /// Whether the first link is known to have left. The screen never claims a
  /// link was sent that was not.
  final bool linkSent;

  final Future<VerificationCheck> Function() onCheck;

  /// Returns null once the link has gone, or why not.
  final Future<String?> Function() onResend;

  /// Signs out, so a different address can be used.
  final VoidCallback onUseDifferentEmail;

  final Speaker speaker;
  final DateTime Function() now;

  /// How long to wait between links. Firebase refuses rapid resends, and a
  /// refusal sounds like the button is broken.
  static const Duration resendCooldown = Duration(seconds: 60);

  static const String notYet = 'That address is not confirmed yet. Open the '
      'link in the email, then press this again. The email can take a minute '
      'to arrive, and may be in the spam folder.';

  static const String checkFailed = 'Could not check just now. Check your '
      'connection, then press this again.';

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _checking = false;
  bool _sending = false;
  late bool _sent = widget.linkSent;
  DateTime? _lastSentAt;
  String? _status;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Duration get _cooldownLeft {
    final last = _lastSentAt;
    if (last == null) return Duration.zero;
    final left =
        VerifyEmailScreen.resendCooldown - widget.now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await widget.onCheck();
    if (!mounted) return;
    setState(() => _checking = false);
    // Verified moves the router on; this screen is going.
    if (result == VerificationCheck.verified) return;
    await _say(result == VerificationCheck.notYet
        ? VerifyEmailScreen.notYet
        : VerifyEmailScreen.checkFailed);
  }

  Future<void> _resend() async {
    if (_sending) return;
    final left = _cooldownLeft;
    if (left > Duration.zero) {
      await _say('A link was sent a moment ago. You can ask for another in '
          '${left.inSeconds} seconds.');
      return;
    }
    setState(() => _sending = true);
    final failure = await widget.onResend();
    if (!mounted) return;
    setState(() => _sending = false);
    if (failure != null) {
      await _say(failure);
      return;
    }
    _lastSentAt = widget.now();
    _sent = true;
    _tick?.cancel();
    _tick = Timer(VerifyEmailScreen.resendCooldown, () {
      if (mounted) setState(() {});
    });
    await _say(widget.email == null
        ? 'A new link is on its way.'
        : 'A new link is on its way to ${widget.email}.');
  }

  Future<void> _say(String message) async {
    setState(() => _status = message);
    await widget.speaker.speak(message);
  }

  @override
  Widget build(BuildContext context) {
    final address = widget.email ?? 'your email address';
    final body = [
      _sent
          ? 'We sent a link to $address. Open it to confirm the address is '
              'yours, then come back here.'
          : 'Your account is made. Before you can use it, confirm that '
              '$address is yours: ask for a link below, then open it.',
      'Until then the app cannot be used, so that nobody can make an account '
          'with an address that is not theirs.',
    ];

    return ViScreen(
      speaker: widget.speaker,
      title: 'Check your email',
      body: body,
      spokenSuffix: 'Three buttons: I have confirmed my email, send the link '
          'again, and use a different email.',
      extra: _status == null
          ? null
          : Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.navyRaised,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _status!,
                  style: const TextStyle(
                      fontSize: 17, height: 1.4, color: AppColors.textPrimary),
                ),
              ),
            ),
      actions: [
        ViButton(
          label: _checking ? 'Checking…' : 'I have confirmed my email',
          icon: Icons.mark_email_read_outlined,
          onPressed: _checking ? null : _check,
        ),
        ViButton(
          label: _sending
              ? 'Sending…'
              : (_sent ? 'Send the link again' : 'Send me the link'),
          detail: _cooldownLeft > Duration.zero
              ? 'You can ask again in a minute'
              : null,
          icon: Icons.forward_to_inbox_outlined,
          kind: ViButtonKind.secondary,
          onPressed: _sending ? null : _resend,
        ),
        ViButton(
          label: 'Use a different email',
          detail: 'Signs out of this account',
          kind: ViButtonKind.quiet,
          onPressed: widget.onUseDifferentEmail,
        ),
      ],
    );
  }
}
