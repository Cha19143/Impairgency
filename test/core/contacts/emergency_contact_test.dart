import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/contacts/emergency_contact.dart';

const mum = EmergencyContact(name: 'Mum', number: '+63 917 000 0000');
const dad = EmergencyContact(name: 'Dad', number: '0918-000-0000');

void main() {
  group('the list is the calling order', () {
    test('and it is said that way', () {
      expect(describeContactOrder(const []), 'No emergency contacts yet.');
      expect(describeContactOrder(const [mum]), 'Mum will be called.');
      expect(describeContactOrder(const [mum, dad]),
          'Mum will be called first, then Dad.');
      expect(
        describeContactOrder(const [
          mum,
          dad,
          EmergencyContact(name: 'Ate', number: '0919')
        ]),
        'Mum will be called first, then Dad, then Ate.',
      );
    });

    test('the same number twice is one person, and the first place wins', () {
      final list = dedupeContacts(const [
        mum,
        dad,
        EmergencyContact(name: 'Mother', number: '+639170000000'),
        EmergencyContact(name: 'Nobody', number: 'no number'),
      ]);
      expect(list.map((c) => c.name), ['Mum', 'Dad']);
    });
  });

  group('the account document', () {
    test('holds the list, and the first under the old name', () {
      final json = emergencyContactsToJson(const [mum, dad]);
      expect((json['emergencyContacts'] as List), hasLength(2));
      expect((json['emergencyContact'] as Map)['name'], 'Mum');
    });

    test('an empty list clears the old name too', () {
      expect(emergencyContactsToJson(const [])['emergencyContact'], isNull);
    });

    test('reads the new shape', () {
      final read = emergencyContactsFrom({
        'emergencyContacts': [
          {'name': 'Mum', 'number': '0917'},
          {'name': 'Dad', 'number': '0918'},
        ],
        'emergencyContact': {'name': 'Mum', 'number': '0917'},
      });
      expect(read.map((c) => c.name), ['Mum', 'Dad']);
    });

    test('reads an account from before there was a list', () {
      final read = emergencyContactsFrom({
        'emergencyContact': {'name': 'Mum', 'number': '0917'},
      });
      expect(read.single.name, 'Mum');
      expect(emergencyContactsFrom(null), isEmpty);
      expect(emergencyContactsFrom({'emergencyContact': null}), isEmpty);
      expect(emergencyContactsFrom({'emergencyContact': 'junk'}), isEmpty);
    });
  });

  group('adding a person', () {
    test('needs a name and a plausible number', () {
      expect(validateNewContact(name: '', number: '0917', existing: const []),
          contains('name'));
      expect(validateNewContact(name: 'Mum', number: '12', existing: const []),
          contains('phone number'));
      expect(validateNewContact(name: 'Mum', number: '0917 000 0000', existing: const []),
          isNull);
    });

    test('refuses a number already on the list, naming who has it', () {
      expect(
        validateNewContact(
            name: 'Mother', number: '+639170000000', existing: const [mum]),
        contains('Mum already has that number'),
      );
    });

    test('stops at the limit and says how to make room', () {
      final full = List.generate(
          kMaxEmergencyContacts,
          (i) => EmergencyContact(name: 'P$i', number: '091700000$i'));
      expect(
        validateNewContact(
            name: 'One more', number: '0918 000 0000', existing: full),
        contains('Remove one'),
      );
    });
  });

  test('numbers are dialled as digits', () {
    expect(mum.dialable, '+639170000000');
    expect(dad.dialable, '09180000000');
  });

  group('the text to everyone', () {
    test('Android lists recipients in the path', () {
      final uri = smsLink(const [mum, dad], 'Help me', ios: false);
      expect(uri.scheme, 'sms');
      expect(uri.path, '+639170000000;09180000000');
      expect(uri.queryParameters['body'], 'Help me');
    });

    test('iOS lists them as addresses', () {
      final uri = smsLink(const [mum, dad], 'Help me', ios: true);
      expect(uri.scheme, 'sms');
      expect(uri.queryParameters['addresses'], '+639170000000,09180000000');
      expect(uri.queryParameters['body'], 'Help me');
    });
  });
}
