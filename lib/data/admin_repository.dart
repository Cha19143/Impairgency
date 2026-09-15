import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/admin/admin_user.dart';
import '../core/places/session_summary.dart';
import '../core/profile/impairment.dart';

export '../core/admin/admin_user.dart';

/// Reads for the web dashboard.
///
/// Everything here is gated by `isAdmin()` in the security rules, which is
/// membership of the `admins` collection — deny-all from every client, granted
/// only in the Firebase console.
class AdminRepository {
  AdminRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// The window the dashboard reports on.
  static const Duration defaultPeriod = Duration(days: 30);

  /// Whether this account is on the roster.
  ///
  /// A plain document read: the rules allow it only for admins, so a non-admin
  /// gets a permission error, which is the answer.
  Future<bool> isAdmin(String uid) async {
    try {
      return (await _db.collection('admins').doc(uid).get()).exists;
    } catch (_) {
      return false;
    }
  }

  /// §1.3's five metrics, over [period].
  Future<UsageOverview> overview({Duration period = defaultPeriod}) async {
    final from = DateTime.now().subtract(period);
    final snap = await _db
        .collection('session_summaries')
        .where('startedAt', isGreaterThan: Timestamp.fromDate(from))
        .orderBy('startedAt', descending: true)
        .limit(2000)
        .get();
    return overviewOf(snap.docs.map(_toSummary).toList());
  }

  /// Recent sessions, newest first — the list a reviewer picks from.
  Future<List<SessionSummary>> recentSessions({int limit = 50}) async {
    final snap = await _db
        .collection('session_summaries')
        .orderBy('startedAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(_toSummary).toList();
  }

  /// Sessions worth a reviewer's attention first — §1.1's actual purpose.
  Future<List<SessionSummary>> sessionsNeedingAttention({int limit = 25}) async {
    final snap = await _db
        .collection('session_summaries')
        .where('concernCount', isGreaterThan: 0)
        .orderBy('concernCount', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(_toSummary).toList();
  }

  /// §1.2's user table: visually impaired users, guardians, administrators,
  /// and the device each is linked to.
  Future<List<AdminUserRow>> users() async {
    final results = await Future.wait([
      _db.collection('users').limit(500).get(),
      _db.collection('admins').limit(100).get(),
      _db.collection('pairings').limit(1000).get(),
    ]);

    final admins = {
      for (final doc in (results[1]).docs) doc.id,
    };

    final links = <String, List<String>>{};
    for (final doc in (results[2]).docs) {
      final data = doc.data();
      final guardian = data['guardianId'] as String?;
      final viUser = data['viUserId'] as String?;
      if (guardian == null || viUser == null) continue;
      links.putIfAbsent(guardian, () => []).add(viUser);
      links.putIfAbsent(viUser, () => []).add(guardian);
    }

    return (results[0]).docs.map((doc) {
      final data = doc.data();
      return AdminUserRow(
        uid: doc.id,
        // Administrator status comes from the roster, not from a field on the
        // user document - a role a client can write is not a role.
        role: admins.contains(doc.id)
            ? 'admin'
            : (data['role'] as String? ?? 'vi'),
        displayName: data['displayName'] as String?,
        email: data['email'] as String?,
        deviceId: data['deviceId'] as String?,
        linkedTo: links[doc.id] ?? const [],
        impairment: data['impairment'] is String
            ? impairmentFromKey(data['impairment'] as String)
            : null,
        category: data['category'] as String?,
        phone: data['phone'] as String?,
        age: (data['age'] as num?)?.toInt(),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      );
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Invitations not yet taken up.
  Future<List<UserInvite>> pendingInvites() async {
    final snap = await _db.collection('user_invites').limit(200).get();
    return snap.docs
        .map((doc) => UserInvite(
              email: doc.id,
              role: doc.data()['role'] as String? ?? 'vi',
              deviceId: doc.data()['deviceId'] as String?,
            ))
        .toList()
      ..sort((a, b) => a.email.compareTo(b.email));
  }

  /// §1.2, without an administrator ever choosing somebody's password.
  ///
  /// Creating the Firebase Auth account from here would need either a server
  /// or the admin picking a password and signing themselves out doing it. The
  /// invited person registers themselves and picks this up on the way in.
  Future<void> invite({
    required String email,
    required String role,
    String? deviceId,
    String? invitedBy,
  }) =>
      _db.collection('user_invites').doc(email.trim().toLowerCase()).set({
        'role': role,
        if (deviceId != null && deviceId.trim().isNotEmpty)
          'deviceId': deviceId.trim(),
        if (invitedBy != null) 'invitedBy': invitedBy,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> withdrawInvite(String email) =>
      _db.collection('user_invites').doc(email.trim().toLowerCase()).delete();

  /// What an administrator may change on someone's account. The security
  /// rules hold the same list, so a key added here and not there is refused
  /// rather than quietly allowed. Consent is not on it: whether someone's
  /// location is shared is theirs to decide, not an administrator's.
  static const Set<String> editableKeys = {
    'name',
    'displayName',
    'age',
    'impairment',
    'impairmentDetail',
    'phone',
    'deviceId',
    'role',
  };

  /// Changes the details on an account.
  ///
  /// A null value removes the field. A change of role also removes the
  /// account's links: a guardian's pairings mean nothing on a visually
  /// impaired account, and the reverse.
  Future<void> updateUser(
    AdminUserRow user,
    Map<String, Object?> changes, {
    required String adminUid,
  }) async {
    final allowed = {
      for (final entry in changes.entries)
        if (editableKeys.contains(entry.key))
          entry.key: entry.value ?? FieldValue.delete(),
    };
    if (allowed.isEmpty) return;
    await _db.collection('users').doc(user.uid).update({
      ...allowed,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    });
    final role = changes['role'];
    if (role is String && role != user.role) {
      await _deletePairingsOf(user.uid);
    }
  }

  /// Removes an account from ImpairGency.
  ///
  /// The Firebase sign-in record cannot be removed from here - that needs the
  /// Admin SDK, and so a server - so the account is marked removed *first*.
  /// The rules then refuse that account every write, the app signs it out,
  /// and if anything below fails part way, pressing Remove again finishes
  /// the job rather than leaving an account half deleted and still usable.
  ///
  /// Saved places and device tokens are not read here to be deleted: that
  /// would put someone's home address in front of an administrator. The
  /// person's own phone erases them when it sees the account was removed.
  Future<void> removeUser(AdminUserRow user, {required String adminUid}) async {
    final uid = user.uid;
    await _db.collection('removed_accounts').doc(uid).set({
      'email': user.email?.trim().toLowerCase(),
      'role': user.role,
      'removedAt': FieldValue.serverTimestamp(),
      'removedBy': adminUid,
    });
    await _deletePairingsOf(uid);
    await _deleteAll(
        _db.collection('pairing_codes').where('ownerId', isEqualTo: uid));
    final history = _db.collection('location_history').doc(uid);
    await _deleteAll(history.collection('fixes'));
    await _deleteAll(history.collection('events'));
    await _deleteAll(_db.collection('users').doc(uid).collection('activity'));
    await _deleteAll(
        _db.collection('session_summaries').where('userId', isEqualTo: uid));
    await _db.collection('users').doc(uid).delete();
  }

  /// Whether [email] belonged to an account that was removed. Its sign-in
  /// record still exists in Firebase, so the address cannot be used again
  /// until that record is deleted in the console.
  Future<bool> wasRemoved(String email) async {
    final snap = await _db
        .collection('removed_accounts')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> _deletePairingsOf(String uid) async {
    await _deleteAll(
        _db.collection('pairings').where('viUserId', isEqualTo: uid));
    await _deleteAll(
        _db.collection('pairings').where('guardianId', isEqualTo: uid));
  }

  /// Deletes everything [query] finds, a batch at a time.
  Future<void> _deleteAll(Query<Map<String, dynamic>> query) async {
    const page = 400;
    while (true) {
      final snap = await query.limit(page).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < page) return;
    }
  }

  /// Writes a summary for the session that just ended.
  ///
  /// Called by the mobile app, not the dashboard, but it lives here so the one
  /// schema has one owner.
  Future<void> publishSummary(SessionSummary summary) =>
      _db.collection('session_summaries').doc(summary.sessionId).set({
        ...summary.toJson(),
        'startedAt': Timestamp.fromDate(summary.startedAt),
      });

  static SessionSummary _toSummary(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return SessionSummary(
      sessionId: data['sessionId'] as String? ?? doc.id,
      userId: data['userId'] as String? ?? '',
      startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      duration: Duration(minutes: (data['minutes'] as num?)?.toInt() ?? 0),
      metresTravelled: (data['metres'] as num?)?.toDouble() ?? 0,
      eventCounts: Map<String, int>.from(
        (data['eventCounts'] as Map?)?.map(
              (k, v) => MapEntry(k as String, (v as num).toInt()),
            ) ??
            const {},
      ),
      discardedFraction: (data['discardedFraction'] as num?)?.toDouble() ?? 0,
      concernCount: (data['concernCount'] as num?)?.toInt() ?? 0,
      placeLabels: List<String>.from(data['placeLabels'] as List? ?? const []),
    );
  }
}
