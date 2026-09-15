import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/auth/email_verification.dart';

void main() {
  final cutoff = DateTime.utc(2026, 9, 14, 16);

  test('a new account that has not confirmed waits', () {
    expect(
      requiresEmailVerification(
          emailVerified: false, createdAt: cutoff.add(const Duration(hours: 1))),
      isTrue,
    );
    expect(
      requiresEmailVerification(emailVerified: false, createdAt: cutoff),
      isTrue,
      reason: 'the cutoff itself is on the new side',
    );
  });

  test('a confirmed account never waits', () {
    expect(
      requiresEmailVerification(
          emailVerified: true, createdAt: cutoff.add(const Duration(days: 1))),
      isFalse,
    );
  });

  test('accounts from before the cutoff keep working', () {
    // Every demo and tester account was made before anyone was asked.
    expect(
      requiresEmailVerification(
          emailVerified: false,
          createdAt: cutoff.subtract(const Duration(minutes: 1))),
      isFalse,
    );
  });

  test('an account with no creation time is let through, not stranded', () {
    expect(
        requiresEmailVerification(emailVerified: false, createdAt: null),
        isFalse);
  });

  test('the shipped cutoff is midnight on 15 September in Manila', () {
    expect(kVerificationRequiredFrom, cutoff);
    expect(kVerificationRequiredFrom.add(const Duration(hours: 8)),
        DateTime.utc(2026, 9, 15));
  });
}
