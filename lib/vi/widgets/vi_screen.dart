import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';

/// The shape every screen in the visually impaired app takes.
///
/// Three guarantees, in one place so no screen can quietly lose them:
///
///  * **It speaks itself on arrival.** Title, then body, then the choices —
///    because a user who cannot see the screen needs to be told what the
///    options are, not just that there are some.
///  * **Actions never scroll away.** The text scrolls; the controls are pinned.
///    Someone who cannot see the screen should not have to discover that the
///    button is below the fold.
///  * **Every control carries a semantic label**, enforced by [ViButton].
class ViScreen extends StatefulWidget {
  const ViScreen({
    super.key,
    required this.title,
    required this.actions,
    this.body = const [],
    this.step,
    this.speaker = const SilentSpeaker(),
    this.spokenSuffix,
    this.extra,
  });

  final String title;

  /// Paragraphs. Spoken one at a time, with a pause between.
  final List<String> body;

  /// Buttons, pinned to the bottom in order.
  final List<Widget> actions;

  /// "Step 3 of 6", or null outside the flow.
  final String? step;

  final Speaker speaker;

  /// Said after the body — usually what the choices are.
  final String? spokenSuffix;

  /// Anything between the body and the actions: a field, a code, switches.
  final Widget? extra;

  @override
  State<ViScreen> createState() => _ViScreenState();
}

class _ViScreenState extends State<ViScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.speaker.speakLines([
        widget.title,
        ...widget.body,
        if (widget.spokenSuffix != null) widget.spokenSuffix!,
      ]);
    });
  }

  @override
  void dispose() {
    widget.speaker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.step != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: Text(
                  widget.step!,
                  style: const TextStyle(
                    fontSize: 14,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 30,
                          height: 1.15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    for (final paragraph in widget.body) ...[
                      const SizedBox(height: 14),
                      Text(
                        paragraph,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (widget.extra != null) ...[
                      const SizedBox(height: 22),
                      widget.extra!,
                    ],
                  ],
                ),
              ),
            ),
            // The actions are pinned, but they still have to fit. A screen
            // with seven choices at 2.0x text scale is taller than the phone,
            // and a Column that cannot scroll silently cuts the last one off -
            // which on Settings was "Back".
            //
            // Flexible, not ConstrainedBox: a ConstrainedBox does not take part
            // in the Column's flex, so it kept its full height and pushed
            // itself below the fold. Flexible makes the body and the actions
            // share what there is, and the actions win because they come with
            // a tighter bound.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.actions,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
