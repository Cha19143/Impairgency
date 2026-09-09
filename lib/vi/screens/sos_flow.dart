import 'package:flutter/material.dart';

import '../../app/theme.dart';
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
    this.contactName,
    this.contactNumber,
    this.guardianCount = 0,
    this.speaker = const SilentSpeaker(),
    this.voice,
    this.voiceController,
  });

  final SosEngine engine;
  final String userId;
  final VoidCallback onFinished;
  final String? contactName;
  final String? contactNumber;
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

  Future<void> _fire() async {
    // Whatever the microphone is doing, the legs come first.
    await widget.voiceController?.stop();
    if (!mounted) return;
    setState(() => _running = true);
    final receipt = await widget.engine.fire(
      userId: widget.userId,
      contactName: widget.contactName,
      contactNumber: widget.contactNumber,
      guardianCount: widget.guardianCount,
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _receipt = receipt;
    });
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
    return SosCountdownScreen(
      contactName: widget.contactName,
      speaker: widget.speaker,
      voice: widget.voice ?? controller?.commands,
      startListening: controller == null
          ? null
          : () => controller.listen(
                only: kCancellationCommands,
                dispatch: false,
                auto: true,
                silenceSpeaker: false,
              ),
      onFire: _fire,
      onCancel: _cancel,
    );
  }
}
