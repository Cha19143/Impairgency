import 'package:flutter/widgets.dart';

import 'speaker.dart';

/// Lines to say when a screen opens.
///
/// Blank lines go. A later line that repeats an earlier one, or that an
/// earlier line already contains as its own words, goes too, so a screen that
/// already says "press Read" does not say "Read" again.
List<String> screenReadingLines(Iterable<String?> lines) {
  final spoken = <String>[];
  for (final raw in lines) {
    if (raw == null) continue;
    final text = raw.trim();
    if (text.isEmpty) continue;
    final lower = text.toLowerCase();
    final already = spoken.any((earlier) {
      if (earlier.toLowerCase() == lower) return true;
      return RegExp('\\b${RegExp.escape(lower)}\\b')
          .hasMatch(earlier.toLowerCase());
    });
    if (already) continue;
    spoken.add(text);
  }
  return spoken;
}

/// The microphone button's label at the moment a screen opens, plus [detail]
/// when that screen shows one.
List<String> openingMicLines({required bool handsFree, String? detail}) => [
      handsFree ? 'Listening for commands' : 'Tap to speak',
      if (detail != null) detail,
    ];

/// Says [lines] once, the first time [ready] is true.
///
/// Later rebuilds, including a new set of lines, are silent. A screen that
/// loads its words after the first frame passes [ready] as false until they
/// are on screen, and they are still said only once.
class AnnounceOnce extends StatefulWidget {
  const AnnounceOnce({
    super.key,
    required this.speaker,
    required this.lines,
    required this.child,
    this.ready = true,
  });

  final Speaker speaker;
  final List<String?> lines;
  final bool ready;
  final Widget child;

  @override
  State<AnnounceOnce> createState() => _AnnounceOnceState();
}

class _AnnounceOnceState extends State<AnnounceOnce> {
  bool _said = false;
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(AnnounceOnce old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  void _schedule() {
    if (_said || _queued || !widget.ready) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || _said || !widget.ready) return;
      _said = true;
      final lines = screenReadingLines(widget.lines);
      if (lines.isEmpty) return;
      widget.speaker.speakLines(lines);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
