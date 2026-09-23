/// The app's own voice, heard back through its own microphone.
///
/// A phone speaker is a few centimetres from the microphone. When the app
/// listens while it is talking - the SOS countdown does, because it has to
/// keep counting - the recogniser transcribes the app as readily as the
/// person holding it. The countdown says "Say cancel, or touch the screen
/// anywhere, to stop this", and a recogniser that hears that sentence hears
/// the word "cancel" in it.
///
/// Pure, so the rule is tested without a speaker or a microphone.
library;

import 'voice_commands.dart';

/// The shortest run of words, in order, that counts as the app's own voice.
///
/// One word alone is never removed: a person saying "cancel" over the top of
/// the countdown has to be heard. Two words in the order the app said them
/// are very unlikely to be the person.
const int kEchoMinRun = 2;

/// [heard] with every run of [kEchoMinRun] or more words that also appears,
/// in the same order, in one of [spoken] taken out.
///
/// It errs towards removing. For a cancel word that is the safe way round: a
/// cancel missed once is said again, or the screen is tapped; a cancel heard
/// in the app's own sentence stops an emergency call nobody meant to stop.
///
/// Except for what the app tells the user to say. "Say create account when
/// you are ready" used to take "create account" out of the user's own
/// "create account", because the app had just said it - so on every screen
/// that says what to say, saying it did nothing, and only a tap worked. A
/// run lying wholly inside one of [instructedPhrases] is kept. The app's
/// sentence heard back is still removed: it runs past the phrase, into
/// "say" or "when you are ready".
String withoutEcho(String heard, Iterable<String> spoken) {
  final words = spokenWords(heard).map(_normalise).toList();
  if (words.isEmpty) return '';
  final echoed = List<bool>.filled(words.length, false);

  for (final sentence in spoken) {
    final sentences = _sentences(sentence);
    final said = _laidEndToEnd(sentences);
    final instructed = _instructedSpans(sentences);
    bool keptAsInstructed(int from, int to) =>
        instructed.any((s) => from >= s.start && to <= s.end);
    if (said.length < kEchoMinRun) {
      // A sentence of one word, heard back whole, is the app too: the name of
      // a button pressed by voice, said as it is pressed, must not press it
      // again from the next window.
      if (said.isNotEmpty && words.length == 1 && words.single == said.single) {
        echoed[0] = true;
      }
      continue;
    }
    for (var i = 0; i < words.length; i++) {
      for (var j = 0; j < said.length; j++) {
        var run = 0;
        while (i + run < words.length &&
            j + run < said.length &&
            words[i + run] == said[j + run]) {
          run++;
        }
        if (run >= kEchoMinRun && !keptAsInstructed(j, j + run)) {
          for (var k = i; k < i + run; k++) {
            echoed[k] = true;
          }
        }
      }
    }
  }

  return [
    for (var i = 0; i < words.length; i++)
      if (!echoed[i]) words[i],
  ].join(' ');
}

/// What [sentence] tells the user to say, phrase by phrase.
///
/// A clause that begins with "say" - on its own or after or, then, and,
/// just - gives the words after it, up to the first word that starts
/// something else ([_phraseEnds]): "Say create account when you are ready"
/// gives "create account". When "say" ends its clause, as in "say: I am
/// okay", the next clause is the phrase. The short clauses that follow in
/// the same sentence are more of the list: "Say scan, read, take me to a
/// place, or help" gives scan, read, take me, and help.
List<String> instructedPhrases(String sentence) {
  final sentences = _sentences(sentence);
  final said = _laidEndToEnd(sentences);
  return [
    for (final span in _instructedSpans(sentences))
      said.sublist(span.start, span.end).join(' '),
  ];
}

/// Words that end an instructed phrase: what follows them is not the thing
/// to say.
const Set<String> _phraseEnds = {
  'or',
  'to',
  'when',
  'and',
  'if',
  'so',
  'then',
  'before',
  'after',
};

/// Words a "say" may come after at the start of its clause.
const Set<String> _beforeSay = {'or', 'then', 'and', 'just', 'now', 'please'};

/// The longest clause that still reads as one more item in a list of things
/// to say.
const int _listItemWords = 5;

/// [text] as sentences, each as clauses of words, split where the
/// punctuation splits it. A list of things to say does not carry on past
/// the end of its sentence.
List<List<List<String>>> _sentences(String text) => [
      for (final sentence in text.split(RegExp(r'(?<=[.!?])\s+')))
        [
          for (final clause in sentence.split(RegExp('[,;:]')))
            spokenWords(clause).map(_normalise).toList(),
        ],
    ];

List<String> _laidEndToEnd(List<List<List<String>>> sentences) => [
      for (final sentence in sentences)
        for (final clause in sentence) ...clause,
    ];

/// Where, in [sentences] laid end to end, the phrases to say are.
List<({int start, int end})> _instructedSpans(
    List<List<List<String>>> sentences) {
  final spans = <({int start, int end})>[];
  var offset = 0;

  void addPhrase(List<String> clause, int from, int at) {
    var end = from;
    while (end < clause.length && !_phraseEnds.contains(clause[end])) {
      end++;
    }
    if (end > from) spans.add((start: at + from, end: at + end));
  }

  for (final clauses in sentences) {
    // After a "say": the next clause is its phrase (colon), or more of its
    // list (commas).
    var sayWaiting = false;
    var inList = false;
    for (final clause in clauses) {
      var from = 0;
      while (from < clause.length && _beforeSay.contains(clause[from])) {
        from++;
      }
      if (from < clause.length && clause[from] == 'say') {
        if (from + 1 < clause.length) {
          addPhrase(clause, from + 1, offset);
          inList = true;
          sayWaiting = false;
        } else {
          sayWaiting = true;
          inList = false;
        }
      } else if (sayWaiting) {
        addPhrase(clause, 0, offset);
        sayWaiting = false;
        inList = true;
      } else if (inList) {
        var start = 0;
        if (start < clause.length && clause[start] == 'or') start++;
        final item = clause.length - start;
        final joins = start == 0 &&
            clause.isNotEmpty &&
            _phraseEnds.contains(clause.first);
        if (item > 0 && item <= _listItemWords && !joins) {
          addPhrase(clause, start, offset);
        } else {
          inList = false;
        }
      }
      offset += clause.length;
    }
  }
  return spans;
}

/// Whether [heard] ends in a word that one of [spoken] carries on from.
///
/// A partial result is a phrase still arriving. When its last word is one the
/// app says with more after it - "cancel" in "Say cancel, or touch the screen"
/// - the next partial may yet make it the app's own sentence, which
/// [withoutEcho] would take out. Acting on the partial first would act on the
/// app. A word the app does not say, or says only at the end of a sentence, is
/// safe to act on before the phrase ends.
bool mayBeEchoStart(String heard, Iterable<String> spoken) {
  final words = spokenWords(heard);
  if (words.isEmpty) return false;
  final last = _normalise(words.last);
  for (final sentence in spoken) {
    final said = spokenWords(sentence).map(_normalise).toList();
    for (var j = 0; j < said.length - 1; j++) {
      if (said[j] == last) return true;
    }
  }
  return false;
}

/// Digits and number words compare equal: the app says "3", a recogniser
/// may write "three", and the other way round.
String _normalise(String word) => _numbers[word] ?? word;

const Map<String, String> _numbers = {
  '0': 'zero',
  '1': 'one',
  '2': 'two',
  '3': 'three',
  '4': 'four',
  '5': 'five',
  '6': 'six',
  '7': 'seven',
  '8': 'eight',
  '9': 'nine',
  '10': 'ten',
};
