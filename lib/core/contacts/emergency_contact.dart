/// The people an SOS reaches, in the order it reaches them.
///
/// One contact became several at the tester's request, and the order is
/// the design decision in this file: **the list is the calling order.** A
/// phone can only place one call at a time, so "fan out" for calls means
/// one after another, and the person at the top of the list is the person
/// rung first. The user arranges the list; the app never reorders it.
///
/// Every number is also written on the SOS event, so a guardian - and the
/// Cloud Function, when there is one - sees the whole list, and the receipt
/// offers a text to all of them at once, which is the one channel a phone
/// can genuinely fan out on its own.
library;

class EmergencyContact {
  const EmergencyContact({required this.name, required this.number});

  final String name;

  /// As typed or picked. Use [dialable] to ring it.
  final String number;

  /// Digits and a leading plus, which is all a dialler wants. Numbers
  /// picked from an address book arrive with spaces, dashes and brackets.
  String get dialable => dialableNumber(number);

  Map<String, Object?> toJson() => {'name': name, 'number': number};

  static EmergencyContact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final number = raw['number'];
    if (name is! String || number is! String) return null;
    if (dialableNumber(number).isEmpty) return null;
    return EmergencyContact(name: name.trim(), number: number.trim());
  }

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact &&
      other.name == name &&
      other.dialable == dialable;

  @override
  int get hashCode => Object.hash(name, dialable);

  @override
  String toString() => 'EmergencyContact($name, $number)';
}

/// How many people an SOS can be told to reach.
///
/// Five, because the calls are sequential and each one the user has to
/// return from. A list of twenty is a list nobody gets to the end of.
const int kMaxEmergencyContacts = 5;

String dialableNumber(String raw) => raw.replaceAll(RegExp(r'[^0-9+]'), '');

/// Reads the list off an account document, old shape or new.
///
/// Accounts made before this release hold one `emergencyContact`; accounts
/// made since hold `emergencyContacts` and, for anything that still reads
/// the old field, the first of them under the old name too.
List<EmergencyContact> emergencyContactsFrom(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final many = data['emergencyContacts'];
  if (many is List) {
    return dedupeContacts(many.map(EmergencyContact.fromJson).nonNulls.toList());
  }
  final one = EmergencyContact.fromJson(data['emergencyContact']);
  return one == null ? const [] : [one];
}

/// What the account document holds: the list, and the first under the old
/// name so nothing that still reads it breaks.
Map<String, Object?> emergencyContactsToJson(List<EmergencyContact> contacts) {
  final clean = dedupeContacts(contacts);
  return {
    'emergencyContacts': clean.map((c) => c.toJson()).toList(),
    'emergencyContact': clean.isEmpty ? null : clean.first.toJson(),
  };
}

/// The same number twice is one person twice; keeps the first, keeps the
/// order, and drops anything with no dialable number.
List<EmergencyContact> dedupeContacts(List<EmergencyContact> contacts) {
  final seen = <String>{};
  final out = <EmergencyContact>[];
  for (final c in contacts) {
    final number = c.dialable;
    if (number.isEmpty || !seen.add(number)) continue;
    out.add(c);
  }
  return out;
}

/// Why a contact cannot be added, or null if it can.
String? validateNewContact({
  required String name,
  required String number,
  required List<EmergencyContact> existing,
}) {
  if (name.trim().isEmpty) return 'Enter the name of the person to call.';
  final clean = dialableNumber(number);
  if (clean.length < 7) return 'That does not look like a phone number.';
  if (existing.any((c) => c.dialable == clean)) {
    return '${existing.firstWhere((c) => c.dialable == clean).name} already '
        'has that number.';
  }
  if (existing.length >= kMaxEmergencyContacts) {
    return 'You can have up to $kMaxEmergencyContacts emergency contacts. '
        'Remove one to add another.';
  }
  return null;
}

/// How the list is read out: position, name, and what the position means.
String describeContactOrder(List<EmergencyContact> contacts) {
  if (contacts.isEmpty) return 'No emergency contacts yet.';
  if (contacts.length == 1) {
    return '${contacts.single.name} will be called.';
  }
  final names = contacts.map((c) => c.name).toList();
  return '${names.first} will be called first, then '
      '${names.sublist(1).join(', then ')}.';
}

/// The link that opens the messaging app with every contact filled in.
///
/// Android and iOS disagree on how to list several recipients, and neither
/// lets an app send without the user pressing Send. That press is the
/// user's, which for an emergency text is the right way round.
Uri smsLink(List<EmergencyContact> contacts, String body, {required bool ios}) {
  final numbers = contacts.map((c) => c.dialable).where((n) => n.isNotEmpty);
  if (ios) {
    return Uri(
      scheme: 'sms',
      path: '/open',
      queryParameters: {'addresses': numbers.join(','), 'body': body},
    );
  }
  return Uri(
    scheme: 'sms',
    path: numbers.join(';'),
    queryParameters: {'body': body},
  );
}
