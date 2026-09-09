import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/session_store.dart';
import '../guardian/guardian_registration.dart';
import 'auth_service.dart';
import 'pairing_repository.dart';

/// Makes a guardian account and links it to the person it watches over.
///
/// Three writes, in an order chosen so each failure leaves something
/// usable behind:
///
///  1. The role is cached on the device *first*. The router reads it the
///     moment Firebase reports a signed-in user, which is before the account
///     document below exists; without this a new guardian was sent to the
///     visually impaired app's "Create your account".
///  2. The account and its document. If this fails, nothing else happened
///     and the sentence says why.
///  3. The pairing code is redeemed. If *this* fails - wrong code, used,
///     expired - the guardian still has an account and is still signed in,
///     and the rejection is returned in the code's own words so the screen
///     can put it under the field.
class GuardianOnboarding {
  GuardianOnboarding({
    required this.auth,
    required this.store,
    required this.pairing,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore;

  final AuthService auth;
  final SessionStore store;
  final PairingRepository pairing;

  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  /// Returns null on success, or a sentence to say and show.
  Future<String?> register(GuardianRegistration registration) async {
    final cached = await store.cachedProfile();
    await store.cacheProfile(cached.copyWith(role: 'guardian'));

    final failure =
        await auth.createAccount(registration.email, registration.password);
    if (failure != null) {
      // Not a guardian after all, or not yet. Leave the cache as it was.
      await store.cacheProfile(cached);
      return failure;
    }
    final uid = auth.uid;
    if (uid == null) return 'The account was created but could not be opened.';

    await _db.collection('users').doc(uid).set({
      ...registration.toUserDocument(uid),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return redeem(registration.pairingCode);
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
}
