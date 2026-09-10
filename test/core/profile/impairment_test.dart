import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/profile/impairment.dart';

void main() {
  group('the list the tester asked for instead of a text box', () {
    test('every type has a label and says what it means for the app', () {
      for (final type in ImpairmentType.values) {
        final choice = kImpairmentChoices[type];
        expect(choice, isNotNull, reason: '$type has no words');
        expect(choice!.label.trim(), isNotEmpty);
        expect(choice.detail.trim(), isNotEmpty);
      }
    });

    test('Other is last, and is the only one that asks for words', () {
      expect(kImpairmentChoices.keys.last, ImpairmentType.other);
      expect(
        validatePersonalInfo(
            name: 'Ana', age: '34', impairment: ImpairmentType.other),
        contains('Describe'),
      );
      expect(
        validatePersonalInfo(
            name: 'Ana',
            age: '34',
            impairment: ImpairmentType.other,
            impairmentDetail: 'macular degeneration'),
        isNull,
      );
    });

    test('the stored key survives a relabel', () {
      for (final type in ImpairmentType.values) {
        expect(impairmentFromKey(impairmentKey(type)), type);
      }
      expect(impairmentFromKey('retinitis'), isNull);
      expect(impairmentFromKey(null), isNull);
    });
  });

  group('what the form refuses, in the order it is filled in', () {
    test('a missing name comes first', () {
      expect(validatePersonalInfo(name: ' ', age: '', impairment: null),
          'Enter your name.');
    });

    test('an age has to be a plausible number', () {
      expect(validatePersonalInfo(name: 'Ana', age: 'old', impairment: null),
          contains('number'));
      expect(validatePersonalInfo(name: 'Ana', age: '0', impairment: null),
          contains('does not look like an age'));
      expect(validatePersonalInfo(name: 'Ana', age: '140', impairment: null),
          contains('does not look like an age'));
    });

    test('an impairment has to be chosen', () {
      expect(validatePersonalInfo(name: 'Ana', age: '34', impairment: null),
          contains('Choose'));
    });

    test('a complete form passes', () {
      expect(
        validatePersonalInfo(
            name: 'Ana', age: '34', impairment: ImpairmentType.lowVision),
        isNull,
      );
    });
  });

  test('what is written to the account', () {
    const info = PersonalInfo(
      name: 'Ana',
      age: 34,
      impairment: ImpairmentType.other,
      impairmentDetail: 'macular degeneration',
      phone: '+639170000000',
    );
    final json = info.toJson();
    expect(json['name'], 'Ana');
    expect(json['displayName'], 'Ana',
        reason: 'the Cloud Function and the dashboard read displayName');
    expect(json['age'], 34);
    expect(json['impairment'], 'other');
    expect(json['impairmentDetail'], 'macular degeneration');
    expect(json['phone'], '+639170000000');

    const bare = PersonalInfo(
        name: 'Ana', age: 34, impairment: ImpairmentType.blind, phone: '');
    expect(bare.toJson().containsKey('phone'), isFalse);
    expect(bare.toJson().containsKey('impairmentDetail'), isFalse);
  });
}
