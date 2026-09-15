import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/safety/safety_notice.dart';
import '../../core/speech/speaker.dart';

/// The first thing the app says, and the first thing it asks for.
///
/// Shown once before onboarding and reachable from the main screen afterwards.
/// It has to be completable with VoiceOver on and Screen Curtain enabled, which
/// is why there is exactly one control on it.
class SafetyNoticeScreen extends StatefulWidget {
  const SafetyNoticeScreen({
    super.key,
    required this.onAcknowledge,
    this.speaker = const SilentSpeaker(),
    this.alreadyAcknowledged = false,
    this.notice = kSafetyNotice,
  });

  final Future<void> Function() onAcknowledge;
  final Speaker speaker;

  /// Revisits get a way out rather than a second acknowledgement.
  final bool alreadyAcknowledged;

  final SafetyNotice notice;

  @override
  State<SafetyNoticeScreen> createState() => _SafetyNoticeScreenState();
}

class _SafetyNoticeScreenState extends State<SafetyNoticeScreen> {
  @override
  void initState() {
    super.initState();
    // Speak after the first frame so the screen reader has announced the route
    // first and the two do not talk over each other.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.speaker.speakLines(widget.notice.lines);
    });
  }

  void _acknowledge() {
    widget.speaker.stop();
    widget.onAcknowledge();
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final label =
        widget.alreadyAcknowledged ? 'Back to main screen' : 'I understand';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // Scrolls rather than clips: at 2.0x text scale this content is
              // taller than any phone.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        notice.headline,
                        style: const TextStyle(
                          fontSize: 30,
                          height: 1.15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    for (final line in notice.lines) ...[
                      Text(
                        line,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.45,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Semantics(
                button: true,
                label: label,
                onTap: _acknowledge,
                child: ExcludeSemantics(
                  child: FilledButton(
                    onPressed: _acknowledge,
                    child: Text(label.toUpperCase()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
