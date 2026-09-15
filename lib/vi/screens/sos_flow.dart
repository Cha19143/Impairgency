import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/contacts/emergency_contact.dart';
import '../../core/sos/sos_countdown.dart';
import '../../core/sos/sos_receipt.dart';
import '../../core/speech/speaker.dart';
import '../../core/voice/voice_commands.dart';
import '../../data/sos_engine.dart';
import '../voice_controller.dart';
import 'sos_countdown_screen.dart';
import 'sos_receipt_screen.dart';

/// Countdown, then the legs, then the receipt.
///
/// One widget owns all three so the receipt cannot be reached without the legs
/// having actually run — there is no route that shows a receipt for an SOS that
/// did not happen.
class SosFlow extends StatefulWidget {
  const SosFlow({
    super.key,
    required this.engine,
    required this.userId,
    required this.onFinished,
    this.contacts = const [],
    this.guardianCount = 0,
    this.speaker = const SilentSpeaker(),
    this.voice,
    this.voiceController,
  });

  final SosEngine engine;

  /// Null when nobody is signed in on this phone. The alarm and the call
  /// still run; the guardian leg says why it could not.
  final String? userId;
  final VoidCallback onFinished;

  /// In calling order. The countdown names the first; the receipt offers
  /// the rest one at a time, and a text to all of them.
  final List<EmergencyContact> contacts;
  final int guardianCount;
  final Speaker speaker;

  /// Spoken commands, for tests that feed them directly.
  final Stream<VoiceCommand>? voice;

  /// The real microphone. When present its [VoiceController.commands] is the
  /// stream the countdown listens to, and the countdown opens it.
  final VoiceController? voiceController;

  @override
  State<SosFlow> createState() => _SosFlowState();
}

class _SosFlowState extends State<SosFlow> {
  SosReceipt? _receipt;
  bool _running = false;

  /// How many contacts have been rung so far.
  int _called = 0;

  EmergencyContact? get _next =>
      _called < widget.contacts.length ? widget.contacts[_called] : null;

  Future<void> _fire() async {
    // Whatever the microphone is doing, the legs come first.
    await widget.voiceController?.stop();
    if (!mounted) return;
    setState(() => _running = true);
    final receipt = await widget.engine.fire(
      userId: widget.userId,
      contacts: widget.contacts,
      guardianCount: widget.guardianCount,
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _called = widget.contacts.isEmpty ? 0 : 1;
      _receipt = receipt;
    });
  }

  Future<void> _callNext() async {
    final contact = _next;
    final receipt = _receipt;
    if (contact == null || receipt == null) return;
    final result = await widget.engine.call(contact);
    if (!mounted) return;
    setState(() {
      _called++;
      _receipt = receipt.withCall(result);
    });
  }

  Future<void> _textAll() async {
    final receipt = _receipt;
    if (receipt == null) return;
    final location = receipt.of(SosLeg.location)?.detail;
    final body = 'Emergency. I need help. '
        '${location == null ? '' : '$location '}'
        'Sent from ImpairGency.';
    final ok = await widget.engine.textAll(widget.contacts, body);
    if (!ok && mounted) {
      await widget.speaker.speak('The message could not be opened.');
    }
  }

  Future<void> _cancel() async {
    await widget.engine.recordCancellation(widget.userId);
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    if (receipt != null) {
      return SosReceiptScreen(
        receipt: receipt,
        speaker: widget.speaker,
        onDone: widget.onFinished,
        nextContact: _next,
        onCallNext: _next == null ? null : _callNext,
        contactCount: widget.contacts.length,
        onTextAll: widget.contacts.isEmpty ? null : _textAll,
        onCallAgain: () {
          setState(() => _receipt = null);
          _fire();
        },
      );
    }

    if (_running) {
      return const Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.red),
              SizedBox(height: 24),
              Text(
                'Calling for help…',
                style: TextStyle(fontSize: 22, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      );
    }

    final controller = widget.voiceController;
    final contactName =
        widget.contacts.isEmpty ? null : widget.contacts.first.name;
    return SosCountdownScreen(
      contactName: contactName,
      speaker: widget.speaker,
      voice: widget.voice ?? controller?.commands,
      startListening: controller == null
          ? null
          : () => controller.listen(
                only: kCancellationCommands,
                dispatch: false,
                auto: true,
                silenceSpeaker: false,
                // Whatever else was listening, this outranks it: a countdown
                // nobody can cancel by voice is not cancellable by a user who
                // has already put the phone away.
                preempt: true,
                // It listens while it talks, and what it says contains the
                // word "cancel". Heard back, that sentence is not the user.
                echoOf: () => [
                  for (var s = kArmingDuration.inSeconds; s >= 0; s--)
                    armingAnnouncement(s, contactName: contactName),
                  kArmingHint,
                ],
              ),
      onFire: _fire,
      onCancel: _cancel,
    );
  }
}
