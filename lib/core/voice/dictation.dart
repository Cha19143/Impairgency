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
  var words = text
      .replaceAll(RegExp(r"[^A-Za-zÀ-ÿñÑ'\-\s.]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  for (final leadIn in _nameLeadIns) {
    final lead = leadIn.split(' ');
    if (words.length > lead.length &&
        [for (var i = 0; i < lead.length; i++) words[i].toLowerCase()]
                .join(' ') ==
            leadIn) {
      words = words.sublist(lead.length);
      break;
    }
  }
  return words
      .take(kMaxNameWords)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

// ---- email ---------------------------------------------------------------

const Map<String, String> _emailWords = {
  'at': '@',
  'dot': '.',
  'period': '.',
  'point': '.',
  'underscore': '_',
  'dash': '-',
  'hyphen': '-',
  'minus': '-',
  'plus': '+',
};

String _email(String text) {
  final tokens = text
      .toLowerCase()
      .replaceAll(RegExp(r'[,;:!?]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  final out = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    // "at sign", "dot com" and the like.
    if (token == 'sign' && i > 0 && tokens[i - 1] == 'at') continue;
    final symbol = _emailWords[token];
    if (symbol != null) {
      out.write(symbol);
      continue;
    }
    final digit = _englishDigits[token];
    if (digit != null) {
      out.write(digit);
      continue;
    }
    out.write(token.replaceAll(RegExp(r'[^a-z0-9@._+\-]'), ''));
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
  var repeat = 1;
  for (final token in tokens) {
    if (token == 'double') {
      repeat = 2;
      continue;
    }
    if (token == 'triple') {
      repeat = 3;
      continue;
    }
    // A country code: "plus six three", or "+63" as the recogniser wrote it.
    if (out.isEmpty && (token == 'plus' || token.startsWith('+'))) {
      out.write('+');
      if (token == 'plus') continue;
    }
    final digits =
        _phoneDigits[token] ?? token.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) continue;
    out.write(digits * repeat);
    repeat = 1;
  }
  final number = out.toString();
  return number == '+' ? '' : number;
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
