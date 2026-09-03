import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/places/session_summary.dart';

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

  /// §1.2's user table.
  Future<List<AdminUserRow>> users() async {
    final snap = await _db.collection('users').limit(500).get();
    return snap.docs.map((doc) {
      final data = doc.data();
      return AdminUserRow(
        uid: doc.id,
        role: data['role'] as String? ?? 'vi',
        displayName: data['displayName'] as String?,
        email: data['email'] as String?,
        deviceId: data['deviceId'] as String?,
      );
    }).toList();
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
