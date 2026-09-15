/// What a guardian fills in, and why it might be refused.
///
/// Flutter-free, like the pairing code rules it leans on, so the validation
/// is tested once here rather than once per screen.
library;

import '../core/auth/email_address.dart';
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

/// The fields of the form, so a refusal can be put under the one it is about.
enum RegisterField { name, email, password, phone, code, general }

/// Why registering did not finish.
class RegisterFailure {
  const RegisterFailure(
    this.message, {
    this.field = RegisterField.general,
    this.accountReady = false,
  });

  /// Said and shown.
  final String message;

  final RegisterField field;

  /// The guardian is signed in and their account document is written: only
  /// the code is left to get right. The screen locks the other fields so a
  /// second press links the account that exists instead of trying to make
  /// it again - which is exactly what "There is already an account with that
  /// email" was the tester hearing.
  final bool accountReady;
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
  final emailProblem = emailAddressProblem(email);
  if (emailProblem != null) return emailProblem;
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
