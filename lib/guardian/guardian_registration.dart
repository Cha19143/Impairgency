/// What a guardian fills in, and why it might be refused.
///
/// Flutter-free, like the pairing code rules it leans on, so the validation
/// is tested once here rather than once per screen.
library;

import '../core/pairing/pairing_code.dart';

class GuardianRegistration {
  const GuardianRegistration({
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
    required this.pairingCode,
  });

  final String name;
  final String email;
  final String password;
  final String phone;

  /// Already normalised - upper case, no punctuation.
  final String pairingCode;

  Map<String, Object?> toUserDocument(String uid) => {
        'uid': uid,
        'email': email.trim(),
        'role': 'guardian',
        'name': name.trim(),
        'displayName': name.trim(),
        'phone': phone,
      };
}

/// Digits and a leading plus, as the SOS engine dials it.
String normalisePhone(String raw) => raw.replaceAll(RegExp(r'[^0-9+]'), '');

/// Why the form cannot be submitted, or null if it can.
///
/// Checks in the order the fields appear, so the first thing said is the
/// first thing on screen.
String? validateGuardianRegistration({
  required String name,
  required String email,
  required String password,
  required String phone,
  required String pairingCode,
}) {
  if (name.trim().isEmpty) return 'Enter your name.';
  final address = email.trim();
  if (!address.contains('@') || address.length < 5) {
    return 'That does not look like an email address.';
  }
  if (password.length < 8) {
    return 'Your password needs at least eight characters.';
  }
  if (normalisePhone(phone).length < 7) {
    return 'That does not look like a phone number.';
  }
  if (!isValidPairingCode(pairingCode)) {
    return pairingRejectionMessage(PairingCodeRejection.malformed);
  }
  return null;
}
