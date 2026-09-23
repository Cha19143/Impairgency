import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/dictation.dart';
import 'package:impairgency/core/voice/dictation_edit.dart';

void main() {
  DictationEdit edit(String heard, {bool spelling = false}) =>
      parseDictationEdit(heard, spelling: spelling);

  group('what a reply asks of the field', () {
    test('keeping it, in any of the ways people say so', () {
      // "Correct", "tama" and "yes that's right" used to become the value.
      for (final said in [
        'done', 'correct', 'yes', "yes that's right", 'tama', 'oo tama',
        'okay po', 'sige', 'tapos na', 'keep it',
      ]) {
        expect(edit(said), isA<EditDone>(), reason: said);
      }
    });

    test('leaving it, and saying it again, are different', () {
      expect(edit('cancel'), isA<EditCancel>());
      expect(edit('leave it'), isA<EditCancel>());
      expect(edit('hindi na'), isA<EditCancel>());
      expect(edit('hindi'), isA<EditRetry>());
      expect(edit('no'), isA<EditRetry>());
      expect(edit('mali'), isA<EditRetry>());
    });

    test('a name with "no" in it is a name', () {
      expect(edit('Nora'), isA<EditReplace>());
      expect(edit('no one at gmail'), isA<EditReplace>());
    });

    test('clear, delete, read back and spell', () {
      expect(edit('start over'), isA<EditClear>());
      expect(edit('burahin lahat'), isA<EditClear>());
      expect(edit('delete last word'), isA<EditDeleteLast>());
      expect(edit('undo'), isA<EditDeleteLast>());
      expect(edit('read it back'), isA<EditReadBack>());
      expect(edit('what did you hear'), isA<EditReadBack>());
      expect(edit('spell it'), isA<EditSpell>());
      expect(edit('baybayin'), isA<EditSpell>());
    });

    test('add puts the rest on the end, as said', () {
      final e = edit('add dot com');
      expect(e, isA<EditAdd>());
      expect((e as EditAdd).text, 'dot com');
      expect((edit('dagdag po cruz') as EditAdd).text, 'po cruz');
    });

    test('anything else is a new value', () {
      final e = edit('ana at yahoo dot com');
      expect((e as EditReplace).text, 'ana at yahoo dot com');
    });

    test('while spelling, it is letters', () {
      final e = edit('c o m', spelling: true);
      expect((e as EditLetters).letters, 'com');
      expect(edit('done', spelling: true), isA<EditDone>());
    });
  });

  group('spelled letters', () {
    test('letters, names of letters, and the phonetic alphabet', () {
      expect(spelledLetters('j o h n'), 'john');
      expect(spelledLetters('jay dee ee ex'), 'jdex');
      expect(spelledLetters('juliet oscar hotel november'), 'john');
    });

    test('"as in", doubles, capitals and digits', () {
      expect(spelledLetters('b as in boy e n'), 'ben');
      expect(spelledLetters('a double l a n'), 'allan');
      expect(spelledLetters('double u i l l'), 'will');
      expect(spelledLetters('capital m a r i a'), 'Maria');
      expect(spelledLetters('a n a nine two'), 'ana92');
      expect(spelledLetters('a n a at'), 'ana@');
    });
  });

  group('editing a value', () {
    test('delete last takes a word, a part of an address, or a digit', () {
      expect(deleteLast(DictationShape.words, 'Jollibee Paseo'), 'Jollibee');
      expect(deleteLast(DictationShape.name, 'Ana'), '');
      expect(deleteLast(DictationShape.email, 'ana@yahoo.com'), 'ana@yahoo.');
      expect(deleteLast(DictationShape.email, 'ana@yahoo.'), 'ana@yahoo');
      expect(deleteLast(DictationShape.phone, '0917'), '091');
      expect(deleteLast(DictationShape.email, ''), '');
    });

    test('more goes on the end the way the field joins it', () {
      expect(joinDictation(DictationShape.email, 'ana@yahoo', '.com'),
          'ana@yahoo.com');
      expect(joinDictation(DictationShape.name, 'Ana', 'Cruz'), 'Ana Cruz');
      expect(joinDictation(DictationShape.phone, '0917', '123'), '0917123');
      expect(joinDictation(DictationShape.words, '', 'clinic'), 'clinic');
    });
  });
}
