import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../voice_controller.dart';
import '../widgets/vi_button.dart';
import '../widgets/voice_mic_button.dart';

/// The three buttons `ui.pdf` drew, plus one.
///
/// This screen is the best thing in the submitted design and it is mostly
/// left alone. Real subtraction is rare; a few enormous, unambiguous choices
/// is the right answer for someone operating a phone by ear.
///
/// The fourth, Read text, is the tester's: reading a label is not scanning
/// a street, and folding it into Scan made Scan worse at both. Below the
/// buttons: consent state that can be seen and changed, the microphone, and
/// a way into the vocabulary.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onScan,
    required this.onAssist,
    required this.onSos,
    required this.onWhatCanISay,
    required this.onSettings,
    this.onReadText,
    this.consent = const {},
    this.speaker = const SilentSpeaker(),
    this.voice,
  });

  final VoidCallback onScan;
  final VoidCallback onAssist;
  final VoidCallback onSos;
  final VoidCallback onWhatCanISay;
  final VoidCallback onSettings;

  /// Books, labels, documents. A fourth button, added at the tester's
  /// request so that Scan stays about the street. Null hides it.
  final VoidCallback? onReadText;

  final Map<String, bool> consent;
  final Speaker speaker;

  /// The microphone. Null hides it — a test, or a build with no voice.
  ///
  /// The screen has said "Say scan, navigate, or help" since the rework, and
  /// until this release nothing was listening when it did.
  final VoiceController? voice;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptThenListen());
  }

  /// Says the prompt, then opens the microphone for the answer. The prompt
  /// is a question; a question nobody is listening to the answer to is the
  /// bug the tester reported.
  Future<void> _promptThenListen() async {
    if (!mounted) return;
    await widget.speaker.speak('Say scan, navigate, or help.');
    if (!mounted) return;
    await widget.voice?.listen(auto: true, silenceSpeaker: false);
  }

  @override
  void dispose() {
    widget.voice?.stop();
    widget.speaker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.consent.entries.where((e) => e.value).map((e) => e.key);

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'ImpairGency',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Settings',
                    child: ExcludeSemantics(
                      child: IconButton(
                        iconSize: 34,
                        onPressed: widget.onSettings,
                        icon: const Icon(Icons.settings_outlined,
                            color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                // Scrollable, not centred. At 2.0x text scale three 88dp
                // buttons plus their detail lines are taller than the screen,
                // and a Column that cannot scroll simply cuts the SOS button
                // off the bottom.
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      ViButton(
                        label: 'SCAN ENVIRONMENT',
                        icon: Icons.document_scanner_outlined,
                        onPressed: widget.onScan,
                      ),
                      ViButton(
                        label: 'SMART ASSISTANCE',
                        icon: Icons.auto_awesome,
                        kind: ViButtonKind.secondary,
                        onPressed: widget.onAssist,
                      ),
                      if (widget.onReadText != null)
                        ViButton(
                          label: 'READ TEXT',
                          detail: 'Books, labels, documents, small print',
                          icon: Icons.menu_book_outlined,
                          kind: ViButtonKind.secondary,
                          onPressed: widget.onReadText,
                        ),
                      ViButton(
                        label: 'EMERGENCY SOS',
                        icon: Icons.emergency_outlined,
                        kind: ViButtonKind.emergency,
                        onPressed: widget.onSos,
                      ),
                    ],
                  ),
                ),
              ),
              // Visible consent state. §7 asks for consent; a user who cannot
              // see a settings screen has no other way to know what is on.
              Semantics(
                button: true,
                label: on.isEmpty
                    ? 'Nothing is being shared. Open settings to change it.'
                    : 'Currently sharing: ${on.join(', ')}. Open settings to '
                        'change it.',
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: widget.onSettings,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final entry in widget.consent.entries)
                            _ConsentChip(name: entry.key, on: entry.value),
                          if (widget.consent.isEmpty)
                            const _ConsentChip(name: 'nothing shared', on: false),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.voice != null) VoiceMicButton(controller: widget.voice!),
              ViButton(
                label: 'What can I say?',
                kind: ViButtonKind.quiet,
                onPressed: widget.onWhatCanISay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentChip extends StatelessWidget {
  const _ConsentChip({required this.name, required this.on});

  final String name;
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
              color: on ? AppColors.green : AppColors.hairline, width: 1.5),
          borderRadius: BorderRadius.circular(8),
          color: on ? AppColors.green.withValues(alpha: 0.12) : null,
        ),
        child: Text(
          '$name ${on ? 'on' : 'off'}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: on ? AppColors.green : AppColors.textSecondary,
          ),
        ),
      );
}
