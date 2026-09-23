/// What someone says while a field is being filled in by voice.
///
/// Each reply used to *replace* the field: "correct", "tama", "yes that's
/// right" were taken as the new value, a two-second pause lost the window,
/// and there was no way to add to what was heard, take a word back, or spell
/// a name the recogniser kept getting wrong. The reply is now read as one of
/// these first, and only as a new value when it is none of them.
///
/// Pure, so the rules are tested without a microphone.
library;

import 'dictation.dart';
import 'voice_commands.dart';

sealed class DictationEdit {
  const DictationEdit();
}

/// Keep the field as it now is.
class EditDone extends DictationEdit {
  const EditDone();
}

/// Leave the field as it was before any of this.
class EditCancel extends DictationEdit {
  const EditCancel();
}

/// What was read back is wrong: ask again.
class EditRetry extends DictationEdit {
  const EditRetry();
}

/// Empty the field and start again.
class EditClear extends DictationEdit {
  const EditClear();
}

/// Take the last word - or the last part of an address, or digit - off.
class EditDeleteLast extends DictationEdit {
  const EditDeleteLast();
}

/// Say it back again.
class EditReadBack extends DictationEdit {
  const EditReadBack();
}

/// From now on, what is said is letters.
class EditSpell extends DictationEdit {
  const EditSpell();
}

/// Put [text] on the end.
class EditAdd extends DictationEdit {
  const EditAdd(this.text);
  final String text;
}

/// Letters spelled out, already joined: to go on the end.
class EditLetters extends DictationEdit {
  const EditLetters(this.letters);
  final String letters;
}

/// A new value altogether.
class EditReplace extends DictationEdit {
  const EditReplace(this.text);
  final String text;
}

/// The words for each edit, for "What can I say" as well as the parser.
const Map<String, List<String>> kDictationEditWords = {
  'Keep it': [
    'done',
    'confirm',
    'correct',
    'that is right',
    'thats right',
    'yes',
    'yeah',
    'okay',
    'ok',
    'keep it',
    'save it',
    'tama',
    'oo',
    'opo',
    'sige',
    'tapos na',
    'ayos',
  ],
  'Leave the field as it was': [
    'cancel',
    'leave it',
    'never mind',
    'nevermind',
    'skip',
    'stop',
    'forget it',
    'huwag',
    'huwag na',
    'hindi na',
  ],
  'Say it again': ['no', 'nope', 'wrong', 'mali', 'hindi'],
  'Start over': [
    'clear',
    'clear it',
    'start over',
    'erase',
    'erase all',
    'burahin lahat',
    'simulan ulit',
  ],
  'Take back the last word': [
    'delete last word',
    'delete the last word',
    'remove last word',
    'remove the last word',
    'delete last',
    'delete that',
    'undo',
    'backspace',
    'burahin ang huli',
  ],
  'Hear it again': [
    'read back',
    'read it back',
    'say it back',
    'what did you hear',
    'repeat',
    'again',
    'pakiulit',
    'ulitin',
  ],
  'Spell it, letter by letter': [
    'spell it',
    'spell',
    'let me spell it',
    'letter by letter',
    'baybayin',
  ],
  'Add more on the end - "add dot com"': [
    'add',
    'append',
    'and then',
    'also',
    'dagdag',
    'idagdag',
  ],
};

const List<String> _doneWords = [
  'done', 'confirm', 'correct', 'that is right', 'thats right', 'yes',
  'yeah', 'okay', 'ok', 'keep it', 'save it', 'tama', 'oo', 'opo', 'sige',
  'tapos na', 'ayos', 'that is it', 'thats it', 'please',
];

List<String> _group(String name) => kDictationEditWords[name]!;

/// What [heard] asks of a field being filled in. [spelling] is set once the
/// user has said "spell it": then anything that is not an edit is letters.
DictationEdit parseDictationEdit(String heard, {bool spelling = false}) {
  final words = spokenWords(heard);
  // "Po" and "please" at the end change nothing.
  while (words.length > 1 && const {'po', 'please'}.contains(words.last)) {
    words.removeLast();
  }
  final said = words.join(' ');
  if (said.isEmpty) return const EditReplace('');

  if (_onlyDoneWords(words)) return const EditDone();
  if (_group('Leave the field as it was').contains(said)) {
    return const EditCancel();
  }
  if (_group('Say it again').contains(said)) return const EditRetry();
  if (_group('Start over').contains(said)) return const EditClear();
  if (_group('Take back the last word').contains(said)) {
    return const EditDeleteLast();
  }
  if (_group('Hear it again').contains(said)) return const EditReadBack();
  if (_group('Spell it, letter by letter').contains(said)) {
    return const EditSpell();
  }

  final add = _group('Add more on the end - "add dot com"');
  for (final prefix in [...add]..sort((a, b) => b.length.compareTo(a.length))) {
    final p = prefix.split(' ');
    if (words.length > p.length && words.take(p.length).join(' ') == prefix) {
      final rest = _afterWords(heard, p.length);
      return spelling
          ? EditLetters(spelledLetters(rest))
          : EditAdd(rest);
    }
  }

  if (spelling) return EditLetters(spelledLetters(heard));
  return EditReplace(heard.trim());
}

/// Whether [words] is nothing but ways of saying "keep it": "yes, that's
/// right", "okay po", "oo tama".
bool _onlyDoneWords(List<String> words) {
  var i = 0;
  var any = false;
  outer:
  while (i < words.length) {
    for (final phrase in [..._doneWords]
      ..sort((a, b) => b.length.compareTo(a.length))) {
      final p = phrase.split(' ');
      if (i + p.length <= words.length &&
          words.sublist(i, i + p.length).join(' ') == phrase) {
        i += p.length;
        if (phrase != 'please') any = true;
        continue outer;
      }
    }
    return false;
  }
  return any;
}

/// [text] without its first [count] words, as it was said.
String _afterWords(String text, int count) {
  final parts = text.trim().split(RegExp(r'\s+'));
  return parts.length <= count ? '' : parts.sublist(count).join(' ');
}

/// [value] with its last word, address part or digit taken off.
String deleteLast(DictationShape shape, String value) {
  final v = value.trimRight();
  if (v.isEmpty) return '';
  switch (shape) {
    case DictationShape.email:
      // "ana@yahoo.com" loses "com", then ".", then "yahoo".
      final run = RegExp(r'[a-z0-9]+$').firstMatch(v);
      return run == null ? v.substring(0, v.length - 1) : v.substring(0, run.start);
    case DictationShape.phone || DictationShape.number:
      return v.substring(0, v.length - 1);
    case DictationShape.words || DictationShape.name:
      final at = v.lastIndexOf(' ');
      return at < 0 ? '' : v.substring(0, at);
  }
}

/// [more] put on the end of [value], the way a field of [shape] joins them.
String joinDictation(DictationShape shape, String value, String more) {
  if (value.isEmpty) return more;
  if (more.isEmpty) return value;
  return switch (shape) {
    DictationShape.email ||
    DictationShape.phone ||
    DictationShape.number =>
      '$value$more',
    DictationShape.words || DictationShape.name => '$value $more',
  };
}

const Map<String, String> _nato = {
  'alpha': 'a', 'alfa': 'a', 'bravo': 'b', 'charlie': 'c', 'delta': 'd',
  'echo': 'e', 'foxtrot': 'f', 'golf': 'g', 'hotel': 'h', 'india': 'i',
  'juliet': 'j', 'juliett': 'j', 'kilo': 'k', 'lima': 'l', 'mike': 'm',
  'november': 'n', 'oscar': 'o', 'papa': 'p', 'quebec': 'q', 'romeo': 'r',
  'sierra': 's', 'tango': 't', 'uniform': 'u', 'victor': 'v',
  'whiskey': 'w', 'xray': 'x', 'yankee': 'y', 'zulu': 'z',
};

const Map<String, String> _spelledSymbols = {
  'at': '@',
  'dot': '.',
  'period': '.',
  'underscore': '_',
  'dash': '-',
  'hyphen': '-',
  'space': ' ',
};

/// Letters spelled out, joined: "j o h n", "juliet oscar", "b as in boy",
/// "double l", "capital m", digits, and "at" and "dot" for an address.
String spelledLetters(String heard) {
  final tokens = foldAccents(heard.toLowerCase())
      .replaceAll(RegExp(r"x-ray"), 'xray')
      .replaceAll(RegExp(r"[,;:!?'’]"), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  final out = StringBuffer();
  var capital = false;
  var repeat = 1;
  var i = 0;
  while (i < tokens.length) {
    final t = tokens[i];
    if (t == 'capital' || t == 'big') {
      capital = true;
      i++;
      continue;
    }
    if (t == 'double' &&
        i + 1 < tokens.length &&
        const {'u', 'you'}.contains(tokens[i + 1])) {
      out.write(capital ? 'W' : 'w');
      capital = false;
      i += 2;
      continue;
    }
    if (t == 'double' || t == 'triple') {
      repeat = t == 'double' ? 2 : 3;
      i++;
      continue;
    }
    if (t == 'under' && i + 1 < tokens.length && tokens[i + 1] == 'score') {
      out.write('_');
      i += 2;
      continue;
    }
    String? piece = _nato[t] ?? _spelledSymbols[t];
    if (piece == null) {
      final digits = numberRun(tokens, i, const {
        'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
        'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      });
      if (digits != null) {
        out.write(digits.digits * repeat);
        repeat = 1;
        i += digits.used;
        continue;
      }
    }
    piece ??= letterNamed(t) ??
        (RegExp(r'^[a-z0-9]$').hasMatch(t) ? t : null);
    if (piece == null) {
      i++;
      continue;
    }
    final letter = capital ? piece.toUpperCase() : piece;
    out.write(letter * repeat);
    capital = false;
    repeat = 1;
    // "b as in boy": the example is not spelled.
    if (i + 2 < tokens.length &&
        tokens[i + 1] == 'as' &&
        tokens[i + 2] == 'in') {
      i += 4;
      continue;
    }
    i++;
  }
  return out.toString();
}
