import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/dictation.dart';

void main() {
  group('an email address', () {
    String email(String heard) => shapeDictation(DictationShape.email, heard);

    test('from "at" and "dot", and letters said one at a time', () {
      expect(email('j d e x at gmail dot com'), 'jdex@gmail.com');
      expect(email('ana dot cruz at yahoo dot com dot ph'),
          'ana.cruz@yahoo.com.ph');
    });

    test('as the recogniser already wrote it', () {
      expect(email('JDex@Gmail.com'), 'jdex@gmail.com');
      expect(email('jdex at gmail.com'), 'jdex@gmail.com');
    });

    test('with digits, underscores and dashes', () {
      expect(email('mark underscore 92 at outlook dot com'),
          'mark_92@outlook.com');
      expect(email('ben dash two at school dot edu'), 'ben-2@school.edu');
    });

    test('keeps the letter o, which is not a zero here', () {
      expect(email('j o h n at gmail dot com'), 'john@gmail.com');
    });

    test('is read back letter by letter, with the common parts as words', () {
      expect(readBack(DictationShape.email, 'jdex92@gmail.com'),
          'j d e x 9 2 at gmail dot com');
      expect(readBack(DictationShape.email, 'ana.cruz@deped.gov.ph'),
          'a n a dot c r u z at d e p e d dot gov dot ph');
    });
  });

  group('a phone number', () {
    String phone(String heard) => shapeDictation(DictationShape.phone, heard);

    test('from digits and number words, in English and Filipino', () {
      expect(phone('0917 123 4567'), '09171234567');
      expect(phone('zero nine one seven one two three four five six seven'),
          '09171234567');
      expect(phone('sero siyam isa pito'), '0917');
      expect(phone('oh nine one seven'), '0917');
    });

    test('with double and triple', () {
      expect(phone('zero nine double one triple five'), '0911555');
    });

    test('with a country code', () {
      expect(phone('+63 917 123 4567'), '+639171234567');
      expect(phone('plus six three nine one seven'), '+63917');
    });

    test('with nothing to dial is nothing', () {
      expect(phone('I do not know it'), '');
    });

    test('is read back in threes', () {
      expect(readBack(DictationShape.phone, '09171234567'),
          '0 9 1, 7 1 2, 3 4 5, 6 7');
      expect(readBack(DictationShape.phone, '0917123456'),
          '0 9 1, 7 1 2, 3 4 5 6',
          reason: 'a last digit on its own joins the group before');
      expect(readBack(DictationShape.phone, '+63917'), 'plus 6 3 9, 1 7');
    });
  });

  group('a name', () {
    String name(String heard) => shapeDictation(DictationShape.name, heard);

    test('is capitalised', () {
      expect(name('maria clara de los santos'), 'Maria Clara De Los Santos');
    });

    test('without what was said before it', () {
      expect(name('her name is ana'), 'Ana');
      expect(name('si Lola Nena'), 'Lola Nena');
      expect(name('ang pangalan ko ay jose rizal'), 'Jose Rizal');
    });

    test('is a name, not a sentence overheard', () {
      expect(name('one two three four five six seven eight').split(' '),
          hasLength(kMaxNameWords));
    });
  });

  group('a number', () {
    String number(String heard) =>
        shapeDictation(DictationShape.number, heard);

    test('from digits or words', () {
      expect(number('34'), '34');
      expect(number('I am 34'), '34');
      expect(number('thirty four'), '34');
      expect(number('seventy-two'), '72');
      expect(number('one hundred'), '100');
    });

    test('with no number in it is nothing', () {
      expect(number('old enough'), '');
    });
  });

  test('anything else is kept as said, tidied', () {
    expect(shapeDictation(DictationShape.words, '  the  clinic on rizal '),
        'the clinic on rizal');
    expect(shapeDictation(DictationShape.words, '   '), '');
  });
}
