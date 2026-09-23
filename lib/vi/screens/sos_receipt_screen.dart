import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/contacts/emergency_contact.dart';
import '../../core/sos/sos_receipt.dart';
import '../../core/speech/speaker.dart';
import '../../core/voice/voice_commands.dart';
import '../voice_controller.dart';
import '../widgets/vi_button.dart';
import '../widgets/voice_mic_button.dart';

/// Said after the receipt when the user can say they are okay.
String afterCallHint({required bool guardianTold}) => guardianTold
    ? 'If you are all right now, say: I am okay. Your guardian will be told.'
    : 'If you are all right now, say: I am okay.';

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
    this.voice,
    this.onOkay,
    this.guardianTold = false,
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

  /// The microphone, listening for "I am okay" once the call is over.
  final VoiceController? voice;

  /// The user said, or pressed, that they are okay. Null where there is no
  /// emergency to clear.
  final Future<void> Function()? onOkay;

  /// Whether a guardian is told when the user says they are okay.
  final bool guardianTold;

  @override
  State<SosReceiptScreen> createState() => _SosReceiptScreenState();
}

class _SosReceiptScreenState extends State<SosReceiptScreen>
    with WidgetsBindingObserver {
  VoiceScopeHandle? _scope;

  /// The dialler put the app behind the call. Back from it, the user is
  /// asked again whether they are okay.
  bool _away = false;
  bool _okaySaid = false;

  String? get _hint => widget.onOkay == null
      ? null
      : afterCallHint(guardianTold: widget.guardianTold);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final voice = widget.voice;
    // The dialler may already have put the app behind the call by the time
    // this is built.
    _away = voice != null && !voice.isForeground;
    if (voice != null && widget.onOkay != null) {
      // The route's own scope for /sos listens to nothing, so that nothing
      // takes the microphone from the countdown. The call is over now, and
      // this screen's scope outranks it.
      _scope = voice.attach(VoiceScope(
        commands: () => kAfterCallCommands,
        onCommand: _onVoice,
        exclusive: true,
        echoOf: () => [widget.receipt.spoken, ?_hint],
        // "Please cancel it" means it is over, here.
        wholePhrase: const {},
      ));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_announce(receipt: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scope?.detach();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_away && !_okaySaid) {
        _away = false;
        unawaited(_announce(receipt: false));
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _away = true;
    }
  }

  /// Says the receipt, then how to say okay - and, when hands-free is off,
  /// listens once for it, as the dashboard does after its own prompt.
  Future<void> _announce({required bool receipt}) async {
    final hint = _hint;
    await widget.speaker.speakLines([
      if (receipt) widget.receipt.spoken,
      ?hint,
    ]);
    final voice = widget.voice;
    if (!mounted || hint == null || voice == null || _okaySaid) return;
    if (voice.handsFree || !voice.isForeground) return;
    await voice.listen(auto: true, silenceSpeaker: false);
  }

  Future<bool> _onVoice(ParsedCommand parsed) async {
    switch (parsed.command) {
      case VoiceCommand.allClear || VoiceCommand.cancel:
        await _okay();
      case VoiceCommand.help:
        // Still in trouble: the alarm and the call again.
        widget.onCallAgain?.call();
      case VoiceCommand.repeat:
        await widget.speaker.speakLines([widget.receipt.spoken, ?_hint]);
      default:
        return false;
    }
    return true;
  }

  Future<void> _okay() async {
    final onOkay = widget.onOkay;
    if (onOkay == null || _okaySaid) return;
    _okaySaid = true;
    await onOkay();
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
                  if (widget.onOkay != null)
                    ViButton(
                      label: "I'm okay",
                      detail: widget.guardianTold
                          ? 'Ends the emergency. Your guardian is told.'
                          : 'Ends the emergency.',
                      icon: Icons.verified_user_outlined,
                      onPressed: () => unawaited(_okay()),
                    ),
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
                  if (widget.voice != null && widget.onOkay != null)
                    VoiceMicButton(
                      controller: widget.voice!,
                      only: kAfterCallCommands,
                      detail: 'Say: I am okay',
                    ),
                  ViButton(
                    label: 'Done',
                    icon: Icons.check,
                    kind: reached && widget.onOkay == null
                        ? ViButtonKind.primary
                        : ViButtonKind.secondary,
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
