import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/reading/reading_session.dart';
import '../../core/speech/speaker.dart';
import '../../core/voice/voice_commands.dart';
import '../../data/text_reader.dart';
import '../voice_controller.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_button_group.dart';
import '../widgets/voice_mic_button.dart';

/// Reading text: books, documents, labels, small print.
///
/// Split from Scan Environment at the tester's request, and the split is
/// the point. Scan is for the street: a stream of frames, one short warning
/// at a time, hazards shouted. This is for a page: one photograph, the words
/// read in pieces at a listener's pace, and three controls a reader
/// actually needs - pause, say that again, next.
///
/// The words are spoken at information priority, so a hazard from nowhere
/// still comes first; nothing else interrupts a line mid-sentence.
class ReadTextScreen extends StatefulWidget {
  const ReadTextScreen({
    super.key,
    required this.onBack,
    this.speaker = const SilentSpeaker(),
    this.reader,
    this.gap = kReadingGap,
    this.onRead,
    this.voice,
  });

  final VoidCallback onBack;

  /// A page was found and is about to be read. Gets the whole text; the
  /// session keeps only its first line for the guardian.
  final void Function(String text)? onRead;
  final Speaker speaker;

  /// Injected in tests so the screen can be exercised without a camera.
  final TextReader? reader;

  /// Silence between pieces. Zero in tests.
  final Duration gap;

  /// "Read", "basahin", "pause", "next", "again". Null means buttons only.
  final VoiceController? voice;

  @override
  State<ReadTextScreen> createState() => _ReadTextScreenState();
}

class _ReadTextScreenState extends State<ReadTextScreen> {
  late final TextReader _reader = widget.reader ?? TextReader();

  bool _ready = false;
  bool _refused = false;
  bool _capturing = false;
  ReadingSession? _session;
  int _run = 0;

  String _status = 'Starting…';

  VoiceScopeHandle? _voiceScope;

  @override
  void initState() {
    super.initState();
    _voiceScope = widget.voice?.attach(VoiceScope(
      commands: _vocabulary,
      onCommand: _onVoice,
      // A page read aloud comes back through the microphone as a stream of
      // words, some of them "read" and "next". A command is a few words said
      // on their own; anything longer while reading is the page.
      maxWords: () => _session?.state == ReadingState.reading ? 4 : 12,
    ));
    _begin();
  }

  /// While a page is being read, only what controls the reading.
  Set<VoiceCommand> _vocabulary() => _session?.state == ReadingState.reading
      ? const {
          VoiceCommand.help,
          VoiceCommand.pause,
          VoiceCommand.next,
          VoiceCommand.repeat,
        }
      : kReadingCommands;

  /// The tester asked to say "read" - or "basahin" - instead of pressing Read.
  ///
  /// Reading is not awaited: it runs to the end of the page, and the
  /// microphone has to be free meanwhile to hear "pause".
  Future<bool> _onVoice(ParsedCommand heard) async {
    final session = _session;
    switch (heard.command) {
      case VoiceCommand.read:
        unawaited(_read());
        return true;
      case VoiceCommand.pause:
        if (session?.state == ReadingState.reading) {
          await _pause();
        } else {
          await widget.speaker.speak('Nothing is being read right now.');
        }
        return true;
      case VoiceCommand.resume:
        if (session?.state == ReadingState.paused) {
          unawaited(_resume());
        } else {
          await widget.speaker.speak(
              'Nothing is paused. Say read to read what is in front of the camera.');
        }
        return true;
      case VoiceCommand.next:
        if (session == null || session.isEmpty) {
          await widget.speaker.speak('Say read first.');
        } else {
          unawaited(_next());
        }
        return true;
      case VoiceCommand.repeat:
        unawaited(_repeat());
        return true;
      case VoiceCommand.back:
        widget.onBack();
        return true;
      default:
        return false;
    }
  }

  Future<void> _begin() async {
    final ok = await _reader.start();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _refused = true;
        _status = 'The camera is off.';
      });
      await widget.speaker.speak(
          'The camera is turned off for this app. Turn it on in Settings to '
          'read text.');
      return;
    }
    setState(() {
      _ready = true;
      _status = 'Point the camera at the text and press Read.';
    });
    await widget.speaker.speak(widget.voice == null
        ? 'Reading text. Hold the phone about thirty centimetres above the '
            'page, then press Read, or tap anywhere on the picture.'
        : 'Reading text. Hold the phone about thirty centimetres above the '
            'page, then say read, or press Read.');
  }

  Future<void> _read() async {
    if (!_ready || _capturing) return;
    _run++;
    await widget.speaker.stop();
    setState(() {
      _capturing = true;
      _status = 'Reading…';
      _session = null;
    });
    final text = await _reader.capture();
    if (!mounted) return;
    setState(() => _capturing = false);
    final session = ReadingSession(text ?? '');
    if (session.isEmpty) {
      setState(() => _status = kNothingToRead);
      await widget.speaker.speak(kNothingToRead);
      return;
    }
    setState(() => _session = session);
    widget.onRead?.call(text ?? '');
    await widget.speaker.speak('${session.total} '
        '${session.total == 1 ? 'line' : 'lines'} found. Reading.');
    await _readFrom(session);
  }

  /// Reads piece after piece until the end, or until paused.
  ///
  /// Each piece is awaited, so it finishes before the next begins; the gap
  /// between them is what makes a page followable by ear.
  Future<void> _readFrom(ReadingSession session) async {
    final run = ++_run;
    while (mounted && run == _run && !session.isPaused) {
      final piece = session.current;
      if (piece == null) {
        setState(() => _status = 'End of the text.');
        await widget.speaker.speak('End of the text. Press Read to read it '
            'again, or point the camera at the next page.');
        return;
      }
      setState(() => _status = '${session.progress}: $piece');
      await widget.speaker.speak(piece);
      if (!mounted || run != _run || session.isPaused) return;
      session.advance();
      if (widget.gap > Duration.zero) {
        await Future<void>.delayed(widget.gap);
      }
    }
  }

  Future<void> _pause() async {
    final session = _session;
    if (session == null) return;
    _run++;
    session.pause();
    await widget.speaker.stop();
    if (!mounted) return;
    setState(() => _status = 'Paused at ${session.progress.toLowerCase()}.');
    await widget.speaker.speak('Paused.');
  }

  Future<void> _resume() async {
    final session = _session;
    if (session == null) return;
    session.resume();
    await _readFrom(session);
  }

  Future<void> _repeat() async {
    final session = _session;
    if (session == null) {
      await widget.speaker.repeat();
      return;
    }
    _run++;
    // The reader advances as soon as a line has been said, so the line the
    // listener missed is the one before the cursor.
    if (session.state != ReadingState.paused) session.back();
    session.pause();
    await widget.speaker.stop();
    final piece = session.current;
    if (piece == null) return;
    setState(() => _status = '${session.progress}: $piece');
    await widget.speaker.speak(piece);
  }

  Future<void> _next() async {
    final session = _session;
    if (session == null) return;
    _run++;
    await widget.speaker.stop();
    session.resume();
    session.advance();
    await _readFrom(session);
  }

  @override
  void dispose() {
    // Stops the reading loop; the next screen's own speech replaces the line
    // in progress. Stopping the shared queue here ran after that screen had
    // started, and silenced it.
    _voiceScope?.detach();
    _run++;
    _reader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _reader.controller;
    final session = _session;
    final reading = session != null && session.state == ReadingState.reading;
    final paused = session != null && session.state == ReadingState.paused;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Semantics(
                label: _status,
                button: true,
                hint: 'Reads the text in front of the camera',
                onTap: _read,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _read,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_ready && controller != null)
                          CameraPreview(controller)
                        else
                          Container(color: AppColors.navyRaised),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.navy.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _status,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                height: 1.3,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // On a phone the reading controls stack, so they are capped and
            // scroll past the cap: the picture keeps room to aim at a page
            // even at twice the text size.
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ViButton(
                      label: _capturing ? 'Reading…' : 'Read',
                      detail: 'Photographs the page and reads it aloud',
                      icon: Icons.menu_book_outlined,
                      onPressed: _ready && !_capturing ? _read : null,
                    ),
                    if (widget.voice != null)
                      VoiceMicButton(
                        controller: widget.voice!,
                        only: kReadingCommands,
                        detail: 'Say read or basahin, pause, next, again',
                      ),
                    if (session != null && !session.isEmpty)
                      ViButtonGroup(
                        buttons: [
                          ViButton(
                            label: paused ? 'Continue' : 'Pause',
                            icon: paused ? Icons.play_arrow : Icons.pause,
                            kind: ViButtonKind.secondary,
                            onPressed: reading
                                ? _pause
                                : paused
                                    ? _resume
                                    : null,
                          ),
                          ViButton(
                            label: 'Say that again',
                            icon: Icons.replay,
                            kind: ViButtonKind.secondary,
                            onPressed: _repeat,
                          ),
                          ViButton(
                            label: 'Next line',
                            icon: Icons.skip_next,
                            kind: ViButtonKind.secondary,
                            onPressed: session.current == null ? null : _next,
                          ),
                        ],
                      ),
                    if (_refused)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Turn the camera on for ImpairGency in Settings to '
                          'read text. Everything else still works.',
                          style: TextStyle(
                              fontSize: 16,
                              height: 1.35,
                              color: AppColors.amber),
                        ),
                      ),
                    ViButton(
                      label: 'Back',
                      kind: ViButtonKind.quiet,
                      onPressed: widget.onBack,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
