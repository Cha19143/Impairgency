import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/contacts/emergency_contact.dart';
import '../../core/sos/sos_receipt.dart';
import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';

/// What actually happened, said and shown.
///
/// `cprwire` had nothing like this: an SOS ended on a screen saying "Dialing…"
/// and the user never learned whether anyone was reached. A leg that failed is
/// named as failed here, in the same words the receipt speaks.
class SosReceiptScreen extends StatefulWidget {
  const SosReceiptScreen({
    super.key,
    required this.receipt,
    required this.onDone,
    this.onCallAgain,
    this.nextContact,
    this.onCallNext,
    this.contactCount = 0,
    this.onTextAll,
    this.speaker = const SilentSpeaker(),
  });

  final SosReceipt receipt;
  final VoidCallback onDone;
  final VoidCallback? onCallAgain;

  /// The next person in the calling order, if there is one, and the button
  /// that rings them. A phone places one call at a time; this is how the
  /// fan-out continues once the user is back from the first.
  final EmergencyContact? nextContact;
  final VoidCallback? onCallNext;

  /// Everyone at once, by text. The one channel that genuinely fans out.
  final int contactCount;
  final VoidCallback? onTextAll;

  final Speaker speaker;

  @override
  State<SosReceiptScreen> createState() => _SosReceiptScreenState();
}

class _SosReceiptScreenState extends State<SosReceiptScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.speaker.speak(widget.receipt.spoken);
    });
  }

  @override
  void dispose() {
    widget.speaker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reached = widget.receipt.anyoneReached;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        widget.receipt.headline,
                        style: TextStyle(
                          fontSize: 30,
                          height: 1.15,
                          fontWeight: FontWeight.bold,
                          color: reached ? AppColors.green : AppColors.amber,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final leg in widget.receipt.legs)
                      _LegRow(result: leg, receipt: widget.receipt),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.nextContact != null && widget.onCallNext != null)
                    ViButton(
                      label: 'Call ${widget.nextContact!.name}',
                      detail: 'The next person on your list',
                      icon: Icons.call,
                      kind: ViButtonKind.emergency,
                      onPressed: widget.onCallNext,
                    ),
                  if (widget.onTextAll != null && widget.contactCount > 0)
                    ViButton(
                      label: widget.contactCount == 1
                          ? 'Text your contact'
                          : 'Text all ${widget.contactCount} contacts',
                      detail: 'Opens a message with your location filled in. '
                          'You press send.',
                      icon: Icons.sms_outlined,
                      kind: ViButtonKind.secondary,
                      onPressed: widget.onTextAll,
                    ),
                  if (!reached && widget.onCallAgain != null)
                    ViButton(
                      label: 'Try again',
                      detail: 'Sound the alarm and call again',
                      icon: Icons.refresh,
                      kind: ViButtonKind.emergency,
                      onPressed: widget.onCallAgain,
                    ),
                  ViButton(
                    label: 'Done',
                    icon: Icons.check,
                    kind: reached ? ViButtonKind.primary : ViButtonKind.secondary,
                    onPressed: widget.onDone,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({required this.result, required this.receipt});

  final LegResult result;
  final SosReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final ok = result.succeeded;
    // The same sentence the receipt speaks, so what is heard and what is read
    // cannot drift apart.
    final text = receipt.sentenceFor(result);

    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ok ? Icons.check_circle : Icons.cancel,
                size: 28,
                color: ok ? AppColors.green : AppColors.red,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.35,
                    color: ok ? AppColors.textPrimary : AppColors.red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
