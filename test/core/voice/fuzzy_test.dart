import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/fuzzy.dart';

void main() {
  group('edit distance', () {
    test('counts insertions, deletions, substitutions and swaps', () {
      expect(editDistance('navigate', 'navigate'), 0);
      expect(editDistance('navigat', 'navigate'), 1);
      expect(editDistance('navigatr', 'navigate'), 1);
      expect(editDistance('naivgate', 'navigate'), 1, reason: 'a swap is one');
      expect(editDistance('assistnce', 'assistance'), 1);
    });

    test('stops counting past the limit', () {
      expect(editDistance('scan', 'basketball', max: 1), 2);
      expect(editDistance('abcdef', 'uvwxyz', max: 2), 3);
    });
  });

  group('words alike', () {
    test('a long word one letter off is the word', () {
      expect(wordsAlike('navigat', 'navigate'), isTrue);
      expect(wordsAlike('asistance', 'assistance'), isTrue);
      expect(wordsAlike('save', 'saved'), isTrue);
    });

    test('short words must be exact', () {
      expect(wordsAlike('scam', 'scan'), isFalse);
      expect(wordsAlike('red', 'read'), isFalse);
      expect(wordsAlike('help', 'held'), isFalse);
      expect(wordsAlike('bread', 'read'), isFalse,
          reason: 'the keyword is the one that has to be long');
    });

    test('cancel words and where words must be exact', () {
      expect(wordsAlike('cancer', 'cancel'), isFalse);
      expect(wordsAlike('there', 'where'), isFalse);
      expect(wordsAlike('hindii', 'hindi'), isFalse);
    });

    test('two letters off is another word', () {
      expect(wordsAlike('navigation', 'navigate'), isFalse);
    });

    test('numbers are not misspellings', () {
      expect(wordsAlike('12345', '12346'), isFalse);
    });
  });

  test('near a keyword: any word of any phrase', () {
    expect(nearKeyword('navigat', ['take me to', 'navigate']), isTrue);
    expect(nearKeyword('bread', ['scan', 'help']), isFalse);
  });
}
