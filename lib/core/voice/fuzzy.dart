/// Words that are nearly the words a command is listening for.
///
/// Recognisers mishear, and people clip words: "navigat for me", "assistanc".
/// Matching was exact, so one letter off was nothing at all. A long word one
/// edit away from a keyword now counts as it. Short words do not - "scan" and
/// "scam", "read" and "red" - and nor do the words that stop things or place
/// them, where a near miss acting would be worse than a miss.
///
/// Pure, so it is tested without a microphone.
library;

/// One edit is allowed only when what was heard is this long at least...
const int kFuzzyMinLength = 4;

/// ...and the word it is matched against is this long. "Save" is "saved";
/// "scam" is not "scan", and "bread" is not "read".
const int kFuzzyLongLength = 5;

/// Words that match only exactly. The cancel words, because a near miss
/// would stop an emergency call or a reading; and where, there and here,
/// which are one letter from each other.
const Set<String> kExactOnlyWords = {
  'cancel',
  'stop',
  'nevermind',
  'teka',
  'tigil',
  'sandali',
  'hindi',
  'huwag',
  'where',
  'there',
  'here',
};

/// Whether [heard] is [keyword], or one edit away from it and long enough
/// for that to be safe. Not symmetric: the keyword - a command's word, or a
/// button's - has to be the long one.
bool wordsAlike(String heard, String keyword) {
  if (heard == keyword) return true;
  if (heard.length < kFuzzyMinLength || keyword.length < kFuzzyLongLength) {
    return false;
  }
  if (kExactOnlyWords.contains(heard) || kExactOnlyWords.contains(keyword)) {
    return false;
  }
  // Digits are numbers, not misspellings.
  if (RegExp(r'\d').hasMatch(heard) || RegExp(r'\d').hasMatch(keyword)) {
    return false;
  }
  return editDistance(heard, keyword, max: 1) <= 1;
}

/// Whether [heard] is near a word of any of [phrases]: the same word, or one
/// edit from a long one. For telling someone trying a command from someone
/// talking.
bool nearKeyword(String heard, Iterable<String> phrases) {
  for (final phrase in phrases) {
    for (final word in phrase.split(' ')) {
      if (wordsAlike(heard, word)) return true;
    }
  }
  return false;
}

/// Edits - an insertion, a deletion, a substitution, or two neighbours
/// swapped - between [a] and [b]. Counting stops past [max]: the answer is
/// then `max + 1`.
int editDistance(String a, String b, {int max = 2}) {
  if ((a.length - b.length).abs() > max) return max + 1;
  // Three rows: the one before the last, the last, and this one.
  var before = List<int>.filled(b.length + 1, 0);
  var last = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0)..[0] = i;
    var best = row[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var d = [
        last[j] + 1,
        row[j - 1] + 1,
        last[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          before[j - 2] + 1 < d) {
        d = before[j - 2] + 1;
      }
      row[j] = d;
      if (d < best) best = d;
    }
    if (best > max) return max + 1;
    before = last;
    last = row;
  }
  final result = last[b.length];
  return result > max ? max + 1 : result;
}
