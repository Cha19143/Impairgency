import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../../core/voice/voice_commands.dart';
import '../widgets/vi_button.dart';

/// The screen ten microphone icons in `ui.pdf` implied and none provided.
///
/// Generated from [kVoiceKeywords] and [kCommandDescriptions] rather than
/// written out, so it cannot drift from what the parser actually accepts. A
/// vocabulary list that is wrong is worse than none: it teaches words that do
/// nothing.
class WhatCanISayScreen extends StatelessWidget {
  const WhatCanISayScreen({
    super.key,
    required this.onBack,
    this.speaker = const SilentSpeaker(),
  });

  final VoidCallback onBack;
  final Speaker speaker;

  /// Everyday commands first, then how to stop things.
  List<VoiceCommand> get _order => [
        ...kEverydayCommands,
        ...VoiceCommand.values.where((c) => !kEverydayCommands.contains(c)),
      ];

  String _spokenList() {
    final lines = <String>['You can say:'];
    for (final command in _order) {
      final words = kVoiceKeywords[command] ?? const [];
      if (words.isEmpty) continue;
      final hint = kArgumentHints[command];
      final example = hint == null ? words.first : '${words.first} $hint';
      lines.add('$example, to ${kCommandDescriptions[command]!.toLowerCase()}.');
    }
    return lines.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Semantics(
                header: true,
                child: Text(
                  'What you can say',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                children: [
                  for (final command in _order)
                    if ((kVoiceKeywords[command] ?? const []).isNotEmpty)
                      _CommandRow(
                        words: kVoiceKeywords[command]!,
                        description: kCommandDescriptions[command]!,
                        after: kArgumentHints[command],
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ViButton(
                    label: 'Read this list aloud',
                    icon: Icons.volume_up_outlined,
                    kind: ViButtonKind.secondary,
                    onPressed: () => speaker.speak(_spokenList()),
                  ),
                  ViButton(
                    label: 'Back',
                    kind: ViButtonKind.quiet,
                    onPressed: onBack,
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

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.words,
    required this.description,
    this.after,
  });

  final List<String> words;
  final String description;

  /// What goes after the words - "a place", "their name".
  final String? after;

  @override
  Widget build(BuildContext context) {
    // Every accepted word, not just the English one. The Filipino variants are
    // the ones a user is most likely not to know are there.
    final spoken = words
        .map((w) => after == null ? '"$w"' : '"$w" $after')
        .join(', ');

    return Semantics(
      label: '$description. Say $spoken.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                spoken,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: AppColors.cyan,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
