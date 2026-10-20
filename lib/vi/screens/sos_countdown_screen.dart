import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/sos/sos_countdown.dart';
import '../../core/speech/screen_reading.dart';
import '../../core/speech/speaker.dart';
import '../../core/voice/voice_commands.dart';

/// Nothing dials until this finishes.
///
/// `ui.pdf` p.12 showed Cancel beside a call already in progress. Cancelling
/// something already done is not cancelling, so the order is inverted: the
/// countdown first, the legs after.
///
/// Three ways to stop it, because a blind user mid-emergency may have any of
/// them available and not the others: say cancel, touch anywhere on the screen,
/// or press the button.
class SosCountdownScreen extends StatefulWidget {
  const SosCountdownScreen({
    super.key,
    required this.onFire,
    required this.onCancel,
    this.contactName,
    this.speaker = const SilentSpeaker(),
    this.voice,
    this.startListening,
    this.duration = kArmingDuration,
  });

  final VoidCallback onFire;
  final VoidCallback onCancel;
  final String? contactName;
  final Speaker speaker;

  /// Spoken commands while the countdown runs. Only cancellation words are
  /// acted on — see [kCancellationCommands].
  final Stream<VoiceCommand>? voice;

  /// Opens the microphone for the cancel word. Called once, as the countdown
  /// starts, because a countdown that only *says* "say cancel" and is not
  /// listening is a countdown that cannot be cancelled by voice. What it
  /// starts keeps listening until the SOS is cancelled or has called.
  final VoidCallback? startListening;

  final Duration duration;

  @override
  State<SosCountdownScreen> createState() => _SosCountdownScreenState();
}

class _SosCountdownScreenState extends State<SosCountdownScreen> {
  late int _secondsLeft = widget.duration.inSeconds;
  Timer? _timer;
  StreamSubscription<VoiceCommand>? _voiceSub;
  bool _settled = false;

  /// Whether the opening lines - the first count and how to stop it - have
  /// been said. Until then the count is not spoken: every spoken line
  /// replaces narration still being said, and "Calling Mum in 2" a second in
  /// cut off "Say cancel, or touch the screen", so nobody heard how to stop
  /// it. The number on screen keeps counting either way.
  bool _hintSaid = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.speaker.speakLines(screenReadingLines([
      armingAnnouncement(_secondsLeft, contactName: widget.contactName),
      ...kArmingHintLines,
      'Nothing has been sent yet.',
      'Or say "cancel", "teka", or "tigil".',
      'CANCEL',
    ])).then((_) => _hintSaid = true));

    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _voiceSub = widget.voice?.listen((command) {
      // help does not cancel: saying "help" during an SOS countdown means the
      // user wants help, and stopping the SOS would be the opposite.
      if (command == VoiceCommand.cancel) _cancel();
    });
    widget.startListening?.call();
  }

  @override
  void dispose() {
    // Not the speaker: "Cancelled. Nothing was sent" is said just before this
    // screen goes, and stopping speech here cut it off.
    _timer?.cancel();
    _voiceSub?.cancel();
    super.dispose();
  }

  void _tick() {
    if (_settled) return;
    final next = _secondsLeft - 1;
    setState(() => _secondsLeft = next);
    if (next <= 0) {
      _fire();
    } else if (_hintSaid) {
      widget.speaker
          .speak(armingAnnouncement(next, contactName: widget.contactName));
    }
  }

  void _fire() {
    if (_settled) return;
    _settled = true;
    _timer?.cancel();
    widget.speaker.speak(armingAnnouncement(0));
    widget.onFire();
  }

  void _cancel() {
    if (_settled) return;
    _settled = true;
    _timer?.cancel();
    widget.speaker.speak(kCancelledAnnouncement);
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final left = _secondsLeft.clamp(0, widget.duration.inSeconds);

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Semantics(
        label: '${armingAnnouncement(left, contactName: widget.contactName)} '
            '$kArmingHint',
        onTap: _cancel,
        child: ExcludeSemantics(
          // The whole screen is the cancel target. Someone who has already put
          // the phone in their pocket cannot find a button, but they can slap
          // the glass.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _cancel,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      widget.contactName == null
                          ? 'CALLING FOR HELP IN'
                          : 'CALLING ${widget.contactName!.toUpperCase()} IN',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                        color: AppColors.red,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 200,
                          height: 200,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.red.withValues(alpha: 0.14),
                            border:
                                Border.all(color: AppColors.red, width: 6),
                          ),
                          child: Text(
                            '$left',
                            style: const TextStyle(
                              fontSize: 96,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Text(
                      'Nothing has been sent yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    Semantics(
                      button: true,
                      label: 'Cancel. Nothing will be sent.',
                      onTap: _cancel,
                      child: ExcludeSemantics(
                        child: Material(
                          color: AppColors.textPrimary,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            onTap: _cancel,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              height: 96,
                              alignment: Alignment.center,
                              child: const Text(
                                'CANCEL',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Or say "cancel", "teka", or "tigil".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
