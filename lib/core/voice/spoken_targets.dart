/// Pressing a button by saying what it says.
///
/// The testers asked for every button to work by voice. A vocabulary per
/// screen would drift from the buttons on it; the buttons' own labels cannot.
///
/// Pure, so the matching is tested without a microphone or a screen.
library;

import 'voice_commands.dart';

/// Said before a button's name without being part of it.
const Set<String> kPressWords = {
  'tap',
  'press',
  'push',
  'click',
  'hit',
  'open',
  'choose',
  'select',
  'pick',
  'pindutin',
  'piliin',
  'buksan',
};

/// Words a label can be said without and still be the same label to the ear.
const Set<String> _filler = {
  'a',
  'an',
  'the',
  'and',
  'or',
  'to',
  'of',
  'for',
  'my',
  'your',
  'this',
  'that',
  'on',
  'in',
  'button',
  'please',
};

/// How many words more than a label a phrase may be and still name it.
/// "Please press the save button" names Save; a sentence that happens to
/// contain the word "back" does not name Back.
const int kTargetSlack = 2;

/// The words that identify [text]: lower case, press words off the front,
/// filler out.
List<String> identifyingWords(String text) {
  final words = spokenWords(text);
  var start = 0;
  while (start < words.length - 1 && kPressWords.contains(words[start])) {
    start++;
  }
  final rest = words.sublist(start);
  final kept = [
    for (final word in rest)
      if (!_filler.contains(word)) word,
  ];
  return kept.isEmpty ? rest : kept;
}

/// Which of [labels] [words] names, by index.
///
/// Every label said exactly, if any was. Otherwise every label all of whose
/// words were said, in a phrase at most [kTargetSlack] words longer - or none
/// at all when [exactOnly]. More than one index means the phrase was
/// ambiguous, and the caller should ask.
List<int> matchSpokenTargets(String words, List<String> labels,
    {bool exactOnly = false}) {
  final said = identifyingWords(words);
  if (said.isEmpty) return const [];
  final exact = <int>[];
  final loose = <int>[];
  for (var i = 0; i < labels.length; i++) {
    final label = identifyingWords(labels[i]);
    if (label.isEmpty) continue;
    if (_same(label, said)) {
      exact.add(i);
    } else if (!exactOnly &&
        said.length <= label.length + kTargetSlack &&
        label.every(said.contains)) {
      loose.add(i);
    }
  }
  return exact.isNotEmpty ? exact : loose;
}

/// Which of [labels] an answer to "Did you mean A, or B?" picks, by index.
///
/// A label named as it would be anywhere else; failing that, the one label
/// the answer's words all belong to - "work", for "Call Mum at work" - or the
/// first, second or third said by position.
List<int> matchChoice(String words, List<String> labels) {
  final named = matchSpokenTargets(words, labels);
  if (named.isNotEmpty) return named;
  final said = identifyingWords(words);
  if (said.isEmpty) return const [];
  for (final (index, ordinals) in _ordinals.indexed) {
    if (index < labels.length && said.any(ordinals.contains)) return [index];
  }
  return [
    for (var i = 0; i < labels.length; i++)
      if (said.every(identifyingWords(labels[i]).contains)) i,
  ];
}

const List<Set<String>> _ordinals = [
  {'first', '1st', 'una', 'unang'},
  {'second', '2nd', 'ikalawa', 'pangalawa'},
  {'third', '3rd', 'ikatlo', 'pangatlo'},
];

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether [words] is nothing but one of [command]'s own phrases.
///
/// Said alone, "back" is the command, even on a screen with a Back button:
/// the screen may do more than the button - Scan asks first. Said as part of
/// a longer label - "Share my location" - the word is not the command
/// "location", and the button wins.
bool isOnlyCommandPhrase(String words, VoiceCommand command) {
  final said = spokenWords(words).join(' ');
  return (kVoiceKeywords[command] ?? const []).contains(said);
}
