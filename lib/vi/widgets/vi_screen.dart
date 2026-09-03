import 'dart:math' as math;

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
///  * **Actions never scroll away.** The text scrolls; the controls are pinned
///    to the bottom. Someone who cannot see the screen should not have to
///    discover that the button is below the fold.
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
  /// The title's style, and the padding around the text it sits in. Named
  /// rather than inlined because [_titleExtent] measures with them: the space
  /// held back for the title has to be the space the title actually takes.
  static const TextStyle _titleStyle = TextStyle(
    fontSize: 30,
    height: 1.15,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  static const EdgeInsets _bodyPadding = EdgeInsets.fromLTRB(24, 18, 24, 8);
  static const EdgeInsets _actionsPadding = EdgeInsets.fromLTRB(24, 10, 24, 12);

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

  /// How tall the title is, here, at this width and this text scale.
  double _titleExtent(BuildContext context, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: widget.title, style: _titleStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(0, maxWidth - _bodyPadding.horizontal));
    final height = painter.height;
    painter.dispose();
    return height + _bodyPadding.vertical;
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // How the height gets split, and why it is not a flex ratio.
                  //
                  // A Column divides the space between flexible children by
                  // their flex factors *before* laying them out, and a loose
                  // child that uses less than its share does not hand the rest
                  // back. Two Flexible children therefore held this screen to
                  // half a phone each whatever they contained: Settings drew
                  // its seven choices inside the top half, four of them below
                  // the fold, above an empty lower half.
                  //
                  // So the actions are not flexible at all. They are laid out
                  // first, at the height they ask for, bounded only by what
                  // the title needs to stay readable — the bound this
                  // LayoutBuilder exists to measure. Whatever is left goes to
                  // the text, which scrolls.
                  final reserved = math.min(
                    _titleExtent(context, constraints.maxWidth),
                    constraints.maxHeight / 2,
                  );

                  // Where the space left over ends up. With something to read,
                  // the text region takes it and the actions settle at the
                  // bottom of the screen, out of the way and under the thumb.
                  // When the title is all the text there is — Settings, where
                  // the choices *are* the screen — they follow it directly
                  // instead of floating below a hole.
                  final hasText =
                      widget.body.isNotEmpty || widget.extra != null;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        fit: hasText ? FlexFit.tight : FlexFit.loose,
                        child: SingleChildScrollView(
                          padding: _bodyPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(widget.title, style: _titleStyle),
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
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight - reserved,
                        ),
                        child: SingleChildScrollView(
                          padding: _actionsPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: widget.actions,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
