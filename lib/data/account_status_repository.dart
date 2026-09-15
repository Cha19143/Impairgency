import 'package:cloud_firestore/cloud_firestore.dart';

/// Said, and shown on the welcome screen, when this phone signs out because
/// the account was removed. Not "something went wrong": what happened, and
/// what can be done about it.
const String kRemovedAccountNotice = 'An administrator removed this account '
    'from ImpairGency, so this phone has signed out. To use the app again, '
    'make a new account or ask the administrator.';

/// Whether an administrator has removed this account.
///
/// Removing an account from the dashboard cannot delete its Firebase sign-in
/// - that needs a server - so it writes `removed_accounts/{uid}` instead. The
/// rules refuse that account every write from then on; this is how the phone
/// finds out, signs out, and says why rather than failing one save at a time.
class AccountStatusRepository {
  AccountStatusRepository({FirebaseFirestore? firestore})
      : _firestore = firestore;

  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('removed_accounts').doc(uid);

  /// True if removed, false if not, and null when it cannot be told - offline,
  /// or a refused read. Null is never treated as removed: signing someone out
  /// because the network dropped would take away the SOS button with it.
  Future<bool?> isRemoved(String uid) async {
    try {
      return (await _doc(uid).get()).exists;
    } catch (_) {
      return null;
    }
  }

  /// Becomes true when the account is removed while the app is open.
  Stream<bool> watchRemoved(String uid) => _doc(uid)
      .snapshots()
      .map((snapshot) => snapshot.exists)
      .handleError((Object _) {});
}
