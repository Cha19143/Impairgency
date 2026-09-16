import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/contacts/emergency_contact.dart';
import '../../core/sos/sos_countdown.dart';
import '../../core/sos/sos_receipt.dart';
import '../../core/speech/speaker.dart';
import '../../core/voice/voice_commands.dart';
import '../../data/sos_engine.dart';
import '../cancel_listener.dart';
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

  /// The spoken commands, shared by the countdown and the seconds after it.
  late final Stream<VoiceCommand>? _commands =
      widget.voice?.asBroadcastStream() ?? widget.voiceController?.commands;

  String? get _contactName =>
      widget.contacts.isEmpty ? null : widget.contacts.first.name;

  /// The microphone, kept open for "cancel" from the countdown until the
  /// dialler opens.
  CancelListener? _listener;

  CancelListener? get _cancelListener {
    final controller = widget.voiceController;
    if (controller == null) return null;
    return _listener ??= CancelListener(
      controller,
      // Each window spans a whole countdown and then some; the listener opens
      // the next one whenever a window ends.
      window: kArmingDuration + const Duration(seconds: 2),
      // It listens while the app talks, and what the app says contains the
      // word "cancel" - and "help". Heard back, that is not the user.
      echoOf: () => [
        for (var s = kArmingDuration.inSeconds; s >= 0; s--)
          armingAnnouncement(s, contactName: _contactName),
        kArmingHint,
        kSosAlarm,
      ],
    );
  }

  /// "Cancel" heard after the countdown, while the alarm sounds and the
  /// position is found.
  StreamSubscription<VoiceCommand>? _firingVoice;

  /// Whether "cancel" can still stop this SOS: until the dialler opens.
  bool _cancellable = false;

  void _stopListening() {
    _cancellable = false;
    unawaited(_firingVoice?.cancel());
    _firingVoice = null;
    unawaited(_listener?.stop());
    _listener = null;
  }

  Future<void> _fire() async {
    if (!mounted) return;
    // The microphone stays open. It used to be closed here, "the legs come
    // first" - but the alarm and the position take seconds before anyone is
    // rung, and a "cancel" in those seconds should still count.
    final cancelled = Completer<void>();
    _cancellable = true;
    unawaited(_firingVoice?.cancel());
    _firingVoice = _commands?.listen((command) {
      if (command == VoiceCommand.cancel &&
          _cancellable &&
          !cancelled.isCompleted) {
        cancelled.complete();
      }
    });
    unawaited(_cancelListener?.run());
    setState(() => _running = true);
    final receipt = await widget.engine.fire(
      userId: widget.userId,
      contacts: widget.contacts,
      guardianCount: widget.guardianCount,
      cancelled: cancelled.future,
      // Past this, "cancel" has nothing left to stop - and the dialler is
      // about to put the app behind the call, where the microphone must not
      // be open.
      onCommitted: _stopListening,
    );
    _stopListening();
    if (!mounted) return;
    if (receipt.cancelled) {
      await widget.speaker.speak(kCancelledAnnouncement);
      if (mounted) widget.onFinished();
      return;
    }
    setState(() {
      _running = false;
      _called = widget.contacts.isEmpty ? 0 : 1;
      _receipt = receipt;
    });
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
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
    _stopListening();
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
      return Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: AppColors.red),
                const SizedBox(height: 24),
                const Text(
                  'Calling for help…',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, color: AppColors.textPrimary),
                ),
                if (_cancellable && widget.voiceController != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Nobody has been called yet. Say "cancel" to stop.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 17, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final listener = _cancelListener;
    return SosCountdownScreen(
      contactName: _contactName,
      speaker: widget.speaker,
      voice: _commands,
      startListening: listener == null ? null : () => unawaited(listener.run()),
      onFire: _fire,
      onCancel: _cancel,
    );
  }
}
