import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/places/session_summary.dart';

/// An account an administrator has asked for, not yet registered.
class UserInvite {
  const UserInvite({required this.email, required this.role, this.deviceId});

  final String email;
  final String role;
  final String? deviceId;
}

/// One row of §1.2's user management table.
class AdminUserRow {
  const AdminUserRow({
    required this.uid,
    required this.role,
    this.displayName,
    this.email,
    this.deviceId,
    this.linkedTo = const [],
  });

  final String uid;

  /// 'vi', 'guardian' or 'admin'. §1.2 asks for all three.
  final String role;

  final String? displayName;
  final String? email;

  /// §1.2's "device connections". Optional — the requirement asks admins to
  /// manage them, not to insist every account has one.
  final String? deviceId;

  /// For a guardian, the users they watch. For a VI user, their guardians.
  final List<String> linkedTo;

  String get name => displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : (email ?? uid);
}

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
