/// Whether something typed into an email field could be an email address.
///
/// It cannot say whether the mailbox exists - only the verification link can
/// prove that, which is why new accounts must follow it (see
/// `email_verification.dart`). What it can do is refuse the obviously made-up
/// addresses the tester typed, the ones the old check let through: anything
/// with an `@` and five characters, `a@b.c` included.
///
/// One definition for every form that takes an address, so they cannot drift.
library;

/// The sentence each form says when the address is refused.
const String kNotAnEmailAddress = 'That does not look like an email address.';

/// Null if [raw] looks like an email address, or why it does not.
String? emailAddressProblem(String raw) {
  final address = raw.trim();
  if (address.isEmpty || address.length > 254) return kNotAnEmailAddress;
  if (RegExp(r'\s').hasMatch(address)) return kNotAnEmailAddress;

  final at = address.indexOf('@');
  if (at <= 0 || at != address.lastIndexOf('@')) return kNotAnEmailAddress;

  final local = address.substring(0, at);
  final domain = address.substring(at + 1);
  if (local.length > 64) return kNotAnEmailAddress;
  if (local.startsWith('.') || local.endsWith('.') || local.contains('..')) {
    return kNotAnEmailAddress;
  }

  final labels = domain.split('.');
  if (labels.length < 2) return kNotAnEmailAddress;
  for (final label in labels) {
    if (label.isEmpty ||
        label.length > 63 ||
        !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(label) ||
        label.startsWith('-') ||
        label.endsWith('-')) {
      return kNotAnEmailAddress;
    }
  }
  if (!RegExp(r'^[A-Za-z]{2,}$').hasMatch(labels.last)) {
    return kNotAnEmailAddress;
  }
  return null;
}
