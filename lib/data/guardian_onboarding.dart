import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../core/session_store.dart';
import '../guardian/guardian_registration.dart';
import 'auth_service.dart';
import 'pairing_repository.dart';

/// The guardian's user document, behind a seam so the order of the steps in
/// [GuardianOnboarding.register] can be tested without Firestore.
abstract interface class GuardianProfileStore {
  /// The document, or null if there is none.
  Future<Map<String, dynamic>?> read(String uid);

  /// Writes a new document, stamped with the server's time.
  Future<void> create(String uid, Map<String, Object?> data);

  /// Merges [data] into an existing document.
  Future<void> merge(String uid, Map<String, Object?> data);
}

class FirestoreGuardianProfileStore implements GuardianProfileStore {
  FirestoreGuardianProfileStore({FirebaseFirestore? firestore})
      : _firestore = firestore;

  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  @override
  Future<Map<String, dynamic>?> read(String uid) async =>
      (await _doc(uid).get()).data();

  @override
  Future<void> create(String uid, Map<String, Object?> data) =>
      _doc(uid).set({...data, 'createdAt': FieldValue.serverTimestamp()});

  @override
  Future<void> merge(String uid, Map<String, Object?> data) =>
      _doc(uid).set(data, SetOptions(merge: true));
}

/// Makes a guardian account and links it to the person it watches over.
///
/// Three things, in an order chosen so each failure leaves something usable
/// behind:
///
///  1. The role is cached on the device *first*. The router reads it the
///     moment Firebase reports a signed-in user, which is before the account
///     document below exists; without this a new guardian was sent to the
///     visually impaired app's "Create your account".
///  2. The account and its document. If this fails, nothing else happened
///     and the sentence says why.
///  3. The pairing code is redeemed. If *this* fails - wrong code, used,
///     expired - the guardian still has an account and is still signed in,
///     and the refusal says so, so the screen can keep the account and ask
///     only for the code again.
///
/// Every step is safe to repeat. The tester pressed Create account a second
/// time because nothing visible had happened, and the second press tried to
/// create the account the first press had already made.
class GuardianOnboarding {
  GuardianOnboarding({
    required this.auth,
    required this.store,
    required this.pairing,
    GuardianProfileStore? profiles,
  }) : _profiles = profiles;

  final AuthService auth;
  final SessionStore store;
  final PairingRepository pairing;

  GuardianProfileStore? _profiles;
  GuardianProfileStore get profiles =>
      _profiles ??= FirestoreGuardianProfileStore();

  /// Returns null once the account exists and is linked, or why not.
  Future<RegisterFailure?> register(GuardianRegistration registration) async {
    final cached = await store.cachedProfile();
    final email = registration.email.trim();
    var accountReady = false;

    try {
      await store.cacheProfile(cached.copyWith(role: 'guardian'));

      if (auth.isSignedIn) {
        // A second press. The account the first press made is still signed
        // in; making it again is what failed before.
        if (!_sameEmail(auth.email, email)) {
          return RegisterFailure(
            'This phone is already signed in as ${auth.email}. Use that '
            'email, or sign out first.',
            field: RegisterField.email,
          );
        }
      } else {
        final failure = await auth.createAccount(email, registration.password);
        if (failure != null) {
          if (!failure.emailInUse) {
            await store.cacheProfile(cached);
            return RegisterFailure(failure.message,
                field: _fieldFor(failure.code));
          }
          // Made on an earlier try - perhaps before the app was closed. The
          // same password is proof enough that it is theirs.
          final refused = await auth.signIn(email, registration.password);
          if (refused != null) {
            await store.cacheProfile(cached);
            return const RegisterFailure(
              'There is already an account with that email. Press "I already '
              'have an account" to sign in, then enter the code.',
              field: RegisterField.email,
            );
          }
        }
      }

      final uid = auth.uid;
      if (uid == null) {
        return const RegisterFailure(
            'The account was made but could not be opened. Try again.');
      }

      final existing = await profiles.read(uid);
      if (existing == null) {
        await profiles.create(uid, registration.toUserDocument(uid));
      } else if (existing['role'] == 'guardian') {
        // Only what the form can change. The role and the creation time are
        // the account's, and the rules refuse a client that rewrites them.
        await profiles.merge(uid, {
          'name': registration.name.trim(),
          'displayName': registration.name.trim(),
          'phone': registration.phone,
        });
      } else {
        await auth.signOut();
        await store.cacheProfile(cached);
        return const RegisterFailure(
          'That email belongs to an ImpairGency user account, not a guardian '
          'account. Use a different email for the guardian account.',
          field: RegisterField.email,
        );
      }
      accountReady = true;

      final refusal = await redeem(registration.pairingCode);
      if (refusal != null) {
        return RegisterFailure(refusal,
            field: RegisterField.code, accountReady: true);
      }
      return null;
    } catch (e) {
      debugPrint('Guardian registration failed: $e');
      if (accountReady) {
        return const RegisterFailure(
          'Your account is ready, but the code could not be checked. Check '
          'your connection, then press the button again.',
          field: RegisterField.code,
          accountReady: true,
        );
      }
      return const RegisterFailure(
          'Something went wrong. Check your connection and try again.');
    }
  }

  /// Redeems a code for the signed-in guardian. Also what the guardian home
  /// screen calls when there is an account and no pairing yet.
  Future<String?> redeem(String code) async {
    final uid = auth.uid;
    if (uid == null) return 'Sign in first, then enter the code they gave you.';
    final result = await pairing.redeem(code, guardianId: uid);
    return switch (result) {
      RedeemSucceeded() => null,
      RedeemFailed(:final spoken) => spoken,
    };
  }

  static bool _sameEmail(String? a, String b) =>
      a != null && a.trim().toLowerCase() == b.trim().toLowerCase();

  static RegisterField _fieldFor(String? code) => switch (code) {
        'invalid-email' => RegisterField.email,
        'weak-password' => RegisterField.password,
        _ => RegisterField.general,
      };
}
