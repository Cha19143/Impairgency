/// Who has to confirm their email address before using the app.
///
/// The tester's report was that a made-up email got in. It did: Create account
/// accepted any address, sent a verification link nobody checked, and let the
/// new account straight through. Now a new account waits at "Check your
/// email" until the link has been opened.
///
/// Accounts made before the cutoff are not held. Every demo account, and every
/// tester's, was made before anyone was asked to verify; locking them out now
/// would break working logins to fix a hole they did not come through.
///
/// Pure, so the rule is tested without Firebase.
library;

/// New accounts from here on must verify: midnight on 15 September 2026 in
/// Manila, the day the feedback came in.
final DateTime kVerificationRequiredFrom = DateTime.utc(2026, 9, 14, 16);

/// Whether an account must confirm its address before going further.
///
/// A missing creation time counts as an older account. Firebase keeps it with
/// the user, so it is not expected to be missing; if it ever is, the person is
/// let through rather than stranded at a screen they may not be able to leave.
bool requiresEmailVerification({
  required bool emailVerified,
  required DateTime? createdAt,
  DateTime? requiredFrom,
}) {
  if (emailVerified || createdAt == null) return false;
  return !createdAt.isBefore(requiredFrom ?? kVerificationRequiredFrom);
}
