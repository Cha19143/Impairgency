/// Filling in a form by voice.
///
/// What a recogniser writes down is not what a field wants. "j d e x at gmail
/// dot com" is an email address; "zero nine one seven, one two three..." is a
/// phone number. And what was heard has to be said back before it is kept -
/// in the form the field will hold, spelled out where a letter matters - so a
/// mishearing is caught by the person who said it, not by the email that never
/// arrives.
///
/// Passwords are never dictated. A password said out loud is not a password.
///
/// Pure, so the shaping is tested without a microphone.
library;

import 'voice_commands.dart';

/// What kind of answer a field takes.
enum DictationShape {
  /// Anything: a place to search for, a label.
  words,

  /// A person's name, capitalised.
  name,

  /// An email address, from "at" and "dot" and spelled-out letters.
  email,

  /// A phone number, as digits.
  phone,

  /// A whole number, such as an age.
  number,
}

/// [heard], shaped into what a field of [shape] holds. Empty when nothing
/// usable was heard.
String shapeDictation(DictationShape shape, String heard) {
  final text = heard.trim();
  if (text.isEmpty) return '';
  return switch (shape) {
    DictationShape.words => text.replaceAll(RegExp(r'\s+'), ' '),
    DictationShape.name => _name(text),
    DictationShape.email => _email(text),
    DictationShape.phone => _phone(text),
    DictationShape.number => _number(text),
  };
}

/// [value] as it is said back, to be checked by ear.
String readBack(DictationShape shape, String value) => switch (shape) {
      DictationShape.email => _spellEmail(value),
      DictationShape.phone => _groupDigits(value),
      _ => value,
    };

// ---- names ---------------------------------------------------------------

/// Said before a name without being part of it.
const List<String> _nameLeadIns = [
  'my name is',
  'her name is',
  'his name is',
  'their name is',
  'the name is',
  'name is',
  'this is',
  'it is',
  'i am',
  'ang pangalan ko ay',
  'ang pangalan ay',
  'ako si',
  'si',
];

/// The most words a name is taken to be. Enough for "Maria Clara de los
/// Santos"; not a sentence overheard.
const int kMaxNameWords = 6;

String _name(String text) {
  final words = stripLeadIn(
      text
          .replaceAll(RegExp(r"[^A-Za-zÀ-ÿñÑ'\-\s.]"), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList(),
      _nameLeadIns);
  return words
      .take(kMaxNameWords)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// [words] without the first of [leadIns] it begins with, if it is followed
/// by something. Compared in lower case; the words kept are as they were.
List<String> stripLeadIn(List<String> words, List<String> leadIns) {
  for (final leadIn in leadIns) {
    final lead = leadIn.split(' ');
    if (words.length > lead.length &&
        [for (var i = 0; i < lead.length; i++) words[i].toLowerCase()]
                .join(' ') ==
            leadIn) {
      return words.sublist(lead.length);
    }
  }
  return words;
}

// ---- email ---------------------------------------------------------------

const Map<String, String> _emailWords = {
  'at': '@',
  'arroba': '@',
  'dot': '.',
  'period': '.',
  'point': '.',
  'tuldok': '.',
  'underscore': '_',
  'dash': '-',
  'hyphen': '-',
  'minus': '-',
  'gitling': '-',
  'plus': '+',
  'dotcom': '.com',
  'dotph': '.ph',
  'dotnet': '.net',
  'dotorg': '.org',
};

/// Symbols and domains said in more than one word, longest first.
const List<(List<String>, String)> _emailPhrases = [
  (['at', 'the', 'rate', 'of'], '@'),
  (['at', 'the', 'rate'], '@'),
  (['at', 'sign'], '@'),
  (['under', 'score'], '_'),
  (['full', 'stop'], '.'),
  (['dot', 'com'], '.com'),
  (['g', 'mail'], 'gmail'),
  (['gee', 'mail'], 'gmail'),
  (['hot', 'mail'], 'hotmail'),
  (['i', 'cloud'], 'icloud'),
  (['out', 'look'], 'outlook'),
  (['double', 'u'], 'w'),
  (['double', 'you'], 'w'),
];

/// Said before an address without being part of it.
const List<String> _emailLeadIns = [
  'my email address is',
  'my email is',
  'my address is',
  'the email address is',
  'the email is',
  'email address is',
  'email is',
  'it is',
  'its',
  'ang email ko ay',
  'ang email ko',
  'email ko ay',
];

/// Said after an address without being part of it.
const List<String> _emailTrailers = [
  'that is it',
  'thats it',
  'thank you',
  'yun lang',
  'thanks',
  'please',
  'lang',
  'po',
];

/// Letters as they are said. Mapped only beside another letter, a letter's
/// name or a digit - "jay dee ee ex" - so "you" and "why" in a sentence stay
/// words.
const Map<String, String> _letterNames = {
  'ay': 'a',
  'bee': 'b',
  'be': 'b',
  'cee': 'c',
  'see': 'c',
  'sea': 'c',
  'dee': 'd',
  'ee': 'e',
  'ef': 'f',
  'eff': 'f',
  'gee': 'g',
  'jee': 'g',
  'aitch': 'h',
  'eych': 'h',
  'eye': 'i',
  'jay': 'j',
  'kay': 'k',
  'el': 'l',
  'ell': 'l',
  'em': 'm',
  'en': 'n',
  'oh': 'o',
  'pee': 'p',
  'cue': 'q',
  'queue': 'q',
  'ar': 'r',
  'are': 'r',
  'es': 's',
  'ess': 's',
  'tee': 't',
  'tea': 't',
  'you': 'u',
  'vee': 'v',
  'ex': 'x',
  'why': 'y',
  'zee': 'z',
  'zed': 'z',
};

/// The letter [word] is the name of - "jay" is j - or null.
String? letterNamed(String word) => _letterNames[word];

bool _isLetter(String token) => RegExp(r'^[a-z]$').hasMatch(token);

/// A letter on its own, a letter's name, or a digit.
bool _spelledPart(String token) =>
    _isLetter(token) ||
    _letterNames.containsKey(token) ||
    _englishDigits.containsKey(token) ||
    RegExp(r'^\d$').hasMatch(token);

/// [text] in plain ASCII: "Nuñez" is typed "nunez" in an address.
String foldAccents(String text) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final out = StringBuffer();
  for (final rune in text.runes) {
    final c = String.fromCharCode(rune);
    final i = from.indexOf(c);
    out.write(i < 0 ? c : to[i]);
  }
  return out.toString();
}

List<String> _tokens(String text) => foldAccents(text.toLowerCase())
    .replaceAll(RegExp(r"[,;:!?'’]"), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList();

String _email(String text) {
  var tokens = stripLeadIn(_tokens(text), _emailLeadIns);
  var trimmed = true;
  while (trimmed && tokens.length > 1) {
    trimmed = false;
    for (final trailer in _emailTrailers) {
      final t = trailer.split(' ');
      if (tokens.length > t.length &&
          tokens.sublist(tokens.length - t.length).join(' ') == trailer) {
        tokens = tokens.sublist(0, tokens.length - t.length);
        trimmed = true;
        break;
      }
    }
  }

  bool at(int i, List<String> phrase) {
    if (i + phrase.length > tokens.length) return false;
    for (var j = 0; j < phrase.length; j++) {
      if (tokens[i + j] != phrase[j]) return false;
    }
    return true;
  }

  final out = StringBuffer();
  var i = 0;
  outer:
  while (i < tokens.length) {
    final token = tokens[i];
    for (final (phrase, symbol) in _emailPhrases) {
      if (at(i, phrase)) {
        out.write(symbol);
        i += phrase.length;
        continue outer;
      }
    }
    // "b as in boy": the letter, and not the boy.
    if (_spelledPart(token) && at(i + 1, const ['as', 'in'])) {
      out.write(_letterNames[token] ?? _englishDigits[token] ?? token);
      i = i + 4 > tokens.length ? tokens.length : i + 4;
      continue;
    }
    if (token == 'capital' || token == 'small' || token == 'lowercase') {
      i++;
      continue;
    }
    final symbol = _emailWords[token];
    if (symbol != null) {
      out.write(symbol);
      i++;
      continue;
    }
    final run = numberRun(tokens, i, _englishDigits);
    if (run != null) {
      out.write(run.digits);
      i += run.used;
      continue;
    }
    final letter = _letterNames[token];
    if (letter != null &&
        ((i > 0 && _spelledPart(tokens[i - 1])) ||
            (i + 1 < tokens.length && _spelledPart(tokens[i + 1])))) {
      out.write(letter);
      i++;
      continue;
    }
    out.write(token.replaceAll(RegExp(r'[^a-z0-9@._+\-]'), ''));
    i++;
  }
  return out.toString();
}

/// Said in whole words when it reads back: a domain everyone knows is clearer
/// as a word than as letters.
const Set<String> _sayableParts = {
  'gmail',
  'yahoo',
  'outlook',
  'hotmail',
  'icloud',
  'com',
  'ph',
  'net',
  'org',
  'edu',
  'gov',
};

String _spellEmail(String email) {
  final parts = <String>[];
  final chunks = RegExp(r'[a-z0-9]+|[@._+\-]').allMatches(email.toLowerCase());
  for (final chunk in chunks) {
    final text = chunk[0]!;
    switch (text) {
      case '@':
        parts.add('at');
      case '.':
        parts.add('dot');
      case '_':
        parts.add('underscore');
      case '-':
        parts.add('dash');
      case '+':
        parts.add('plus');
      default:
        parts.add(
            _sayableParts.contains(text) ? text : text.split('').join(' '));
    }
  }
  return parts.join(' ');
}

// ---- numbers -------------------------------------------------------------

/// Digits said as words. Only English ones inside an email address, where
/// "lima" may be a name and "o" is a letter.
const Map<String, String> _englishDigits = {
  'zero': '0',
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
};

/// Digits said as words in a phone number, in English and Filipino.
const Map<String, String> _phoneDigits = {
  ..._englishDigits,
  'oh': '0',
  'o': '0',
  'sero': '0',
  'isa': '1',
  'dalawa': '2',
  'tatlo': '3',
  'apat': '4',
  'lima': '5',
  'anim': '6',
  'pito': '7',
  'walo': '8',
  'siyam': '9',
};

String _phone(String text) {
  final tokens = text
      .toLowerCase()
      .replaceAll(RegExp(r'[,.;:!?()]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  final out = StringBuffer();
  var i = 0;
  while (i < tokens.length) {
    final token = tokens[i];
    // A country code: "plus six three", or "+63" as the recogniser wrote it.
    if (out.isEmpty && (token == 'plus' || token.startsWith('+'))) {
      out.write('+');
      if (token == 'plus') {
        i++;
        continue;
      }
    }
    final run = numberRun(tokens, i, _phoneDigits);
    if (run != null) {
      out.write(run.digits);
      i += run.used;
      continue;
    }
    out.write(token.replaceAll(RegExp(r'[^0-9]'), ''));
    i++;
  }
  final number = out.toString();
  return number == '+' ? '' : number;
}

/// The digits said in words from [start]: "nine two", "twenty two",
/// "double seven", "one hundred five". Null when [start] is not a number
/// word. [digits] names the single digits, which differ between an email
/// address and a phone number.
({String digits, int used})? numberRun(
    List<String> tokens, int start, Map<String, String> digits) {
  final out = StringBuffer();
  var i = start;
  var repeat = 1;
  int? small(int at) {
    if (at >= tokens.length) return null;
    final t = tokens[at];
    return _units[t] ?? _tens[t];
  }

  while (i < tokens.length) {
    final t = tokens[i];
    if (t == 'double' || t == 'triple') {
      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      if (next == null || digits[next] == null) break;
      repeat = t == 'double' ? 2 : 3;
      i++;
      continue;
    }
    final digit = digits[t];
    if (digit != null) {
      out.write(digit * repeat);
      repeat = 1;
      i++;
      continue;
    }
    final unit = _units[t];
    if (unit != null && unit >= 10) {
      out.write('$unit');
      i++;
      continue;
    }
    final ten = _tens[t];
    if (ten != null) {
      final next = i + 1 < tokens.length ? _units[tokens[i + 1]] : null;
      if (next != null && next > 0 && next < 10) {
        out.write('${ten + next}');
        i += 2;
      } else {
        out.write('$ten');
        i++;
      }
      continue;
    }
    if (t == 'hundred' && out.isNotEmpty) {
      // "one hundred five" is 105; "one hundred twenty three", 123.
      var rest = 0;
      var used = 1;
      final a = small(i + 1);
      if (a != null) {
        rest = a;
        used = 2;
        final b = small(i + 2);
        if (a >= 20 && a % 10 == 0 && b != null && b < 10 && b > 0) {
          rest += b;
          used = 3;
        }
      }
      out.write(rest.toString().padLeft(2, '0'));
      i += used;
      continue;
    }
    break;
  }
  if (out.isEmpty) return null;
  return (digits: out.toString(), used: i - start);
}

/// Digits in threes, so they are heard as a number read out rather than as
/// one long word.
String _groupDigits(String value) {
  final plus = value.startsWith('+');
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  final groups = <String>[];
  for (var i = 0; i < digits.length; i += 3) {
    final end = i + 3 > digits.length ? digits.length : i + 3;
    groups.add(digits.substring(i, end).split('').join(' '));
  }
  // A last group of one is hard to hear on its own: it joins the one before.
  if (groups.length > 1 && groups.last.length == 1) {
    final last = groups.removeLast();
    groups[groups.length - 1] = '${groups.last} $last';
  }
  return '${plus ? 'plus ' : ''}${groups.join(', ')}';
}

const Map<String, int> _units = {
  'zero': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
};

const Map<String, int> _tens = {
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};

String _number(String text) {
  final digits = RegExp(r'\d+').firstMatch(text)?.group(0);
  if (digits != null) return digits;
  var total = 0;
  var heard = false;
  for (final word in spokenWords(text.replaceAll('-', ' '))) {
    if (_units.containsKey(word)) {
      total += _units[word]!;
      heard = true;
    } else if (_tens.containsKey(word)) {
      total += _tens[word]!;
      heard = true;
    } else if (word == 'hundred' && heard) {
      total *= 100;
    }
  }
  return heard ? '$total' : '';
}
