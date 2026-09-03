import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/pairing/pairing_code.dart';

sealed class RedeemResult {
  const RedeemResult();
}

class RedeemSucceeded extends RedeemResult {
  const RedeemSucceeded({required this.viUserId, required this.code});

  final String viUserId;
  final String code;
}

class RedeemFailed extends RedeemResult {
  const RedeemFailed(this.reason);

  final PairingCodeRejection reason;

  String get spoken => pairingRejectionMessage(reason);
}

/// Issuing and redeeming the invitation codes that connect a guardian to a
/// visually impaired user.
///
/// The guardian app has no other way in. Without this, the guardian dashboard
/// in the submitted design is a screen nobody can reach.
class PairingRepository {
  PairingRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _codes =>
      _db.collection('pairing_codes');

  CollectionReference<Map<String, dynamic>> get _pairings =>
      _db.collection('pairings');

  /// Deterministic, and matched by the security rules. A pairing whose id does
  /// not equal this is rejected server-side.
  static String pairingId(String guardianId, String viUserId) =>
      '${guardianId}_$viUserId';

  /// Creates a fresh code for [ownerId] to read aloud.
  ///
  /// Retries on collision rather than trusting a single draw. With 214 million
  /// combinations a clash is vanishingly unlikely, but "vanishingly unlikely"
  /// is not "impossible", and the failure would be one user handing out
  /// another user's invitation.
  Future<String> issueCode(String ownerId, {DateTime? now}) async {
    final issuedAt = now ?? DateTime.now();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = generatePairingCode();
      final ref = _codes.doc(code);
      if ((await ref.get()).exists) continue;
      await ref.set({
        'ownerId': ownerId,
        'usedBy': null,
        'expiresAt': Timestamp.fromDate(issuedAt.add(kPairingCodeLifetime)),
        'issuedAt': Timestamp.fromDate(issuedAt),
      });
      return code;
    }
    throw StateError('Could not allocate an unused pairing code.');
  }

  /// Invalidates a code the user no longer wants outstanding.
  Future<void> revokeCode(String code) =>
      _codes.doc(normalisePairingCode(code)).delete();

  /// Redeems [input] on behalf of [guardianId].
  ///
  /// Two writes, in this order and not batched: the code is marked used, then
  /// the pairing is created. They cannot be batched because the rule guarding
  /// the pairing reads the code document, and inside a batch it would still see
  /// the pre-batch state.
  ///
  /// If the second write fails the code is spent with no pairing to show for
  /// it, and the rules deliberately forbid un-spending it. That fails closed -
  /// the user issues another code - which is the right way round for something
  /// that grants a stranger sight of where someone lives. Moving redemption
  /// into a Cloud Function would make it atomic and allow rate limiting; that
  /// is the same change this wants for enumeration resistance.
  Future<RedeemResult> redeem(String input, {required String guardianId}) async {
    if (!isValidPairingCode(input)) {
      return const RedeemFailed(PairingCodeRejection.malformed);
    }
    final code = normalisePairingCode(input);
    final ref = _codes.doc(code);

    final snapshot = await ref.get();
    if (!snapshot.exists) {
      return const RedeemFailed(PairingCodeRejection.notFound);
    }

    final data = snapshot.data()!;
    if (data['usedBy'] != null) {
      return const RedeemFailed(PairingCodeRejection.alreadyUsed);
    }

    final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
    if (expiresAt == null || expiresAt.isBefore(DateTime.now())) {
      return const RedeemFailed(PairingCodeRejection.expired);
    }

    final viUserId = data['ownerId'] as String;

    // The client checks above are for a clear spoken message. These two writes
    // are what actually decides it - the rules re-check used and expired
    // server-side, so a stale read cannot be used to slip a spent code through.
    await ref.update({'usedBy': guardianId});
    await _pairings.doc(pairingId(guardianId, viUserId)).set({
      'guardianId': guardianId,
      'viUserId': viUserId,
      'code': code,
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    return RedeemSucceeded(viUserId: viUserId, code: code);
  }

  /// The users this guardian watches over.
  Stream<List<String>> watchedUsers(String guardianId) => _pairings
      .where('guardianId', isEqualTo: guardianId)
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()['viUserId'] as String).toList());

  Future<void> unpair(String guardianId, String viUserId) =>
      _pairings.doc(pairingId(guardianId, viUserId)).delete();
}
