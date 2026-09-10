/// Reading a page aloud: in pieces, at the listener's pace.
///
/// A hazard warning is one sentence said once, fast. A page of text is the
/// opposite: it is long, the listener may lose the thread, and "say that
/// again" has to mean the last *line*, not the whole page. So recognised
/// text is cut into lines and sentences, and this session keeps the place -
/// which piece is being read, whether the reader has paused, what "repeat"
/// and "next" refer to.
///
/// Pure, so the cutting and the place-keeping are tested without a camera.
library;

/// Cuts recognised text into pieces short enough to hold in the ear.
///
/// Lines first - OCR returns them, and a label or a menu is lines - then
/// sentences within a line, so a paragraph of prose is not one breath.
/// Empty pieces and stray punctuation are dropped.
List<String> splitIntoChunks(String text) {
  final chunks = <String>[];
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final sentences = line
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(s));
    chunks.addAll(sentences);
  }
  return chunks;
}

/// What the reader says when the camera saw no words.
const String kNothingToRead =
    'I could not find any text. Hold the phone steady, about thirty '
    'centimetres from the page, and try again.';

enum ReadingState {
  /// Nothing captured yet, or the last capture had no text.
  empty,

  /// Reading, piece by piece.
  reading,

  /// Stopped mid-page; [ReadingSession.resume] continues from the same
  /// piece.
  paused,

  /// The last piece has been read.
  finished,
}

class ReadingSession {
  ReadingSession(String text) : chunks = splitIntoChunks(text);

  final List<String> chunks;
  int _index = 0;
  bool _paused = false;

  bool get isEmpty => chunks.isEmpty;

  /// The piece being read, or null when there is nothing left.
  String? get current => _index < chunks.length ? chunks[_index] : null;

  int get index => _index;
  int get total => chunks.length;

  ReadingState get state {
    if (chunks.isEmpty) return ReadingState.empty;
    if (_index >= chunks.length) return ReadingState.finished;
    return _paused ? ReadingState.paused : ReadingState.reading;
  }

  bool get isPaused => _paused;

  /// Moves on. Returns the next piece, or null at the end.
  String? advance() {
    if (_index < chunks.length) _index++;
    return current;
  }

  /// Goes back one piece, so "repeat" after the reader moved on still means
  /// the line the listener missed.
  String? back() {
    if (_index > 0) _index--;
    return current;
  }

  void pause() => _paused = true;

  void resume() => _paused = false;

  void restart() {
    _index = 0;
    _paused = false;
  }

  /// "Line 3 of 12", for the screen and for the reader on request.
  String get progress =>
      chunks.isEmpty ? 'Nothing to read' : 'Line ${_index + 1} of ${chunks.length}';
}

/// Between pieces: enough to hear where one line ends, not so much that a
/// page takes all afternoon.
const Duration kReadingGap = Duration(milliseconds: 450);
