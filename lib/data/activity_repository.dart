import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/guardian/activity.dart';

/// What the session calls. The real one below; tests hand in a recorder.
abstract interface class ActivityRecorder {
  Future<void> record(String uid, ActivityEvent event);
}

/// `users/{uid}/activity`: the rows behind the guardian's "recent activity".
///
/// Written by the user's phone, read by a paired guardian, both only while
/// `consent.activity` is on - the rules decide, this class just asks. Kept
/// short: a guardian wants the last few things, and the user did not agree
/// to a diary.
class ActivityRepository implements ActivityRecorder {
  ActivityRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Rows older than this are removed the next time the user writes one.
  static const Duration retention = Duration(days: 7);

  /// How many the guardian is shown.
  static const int recentLimit = 10;

  bool _pruned = false;

  CollectionReference<Map<String, dynamic>> _activity(String uid) =>
      _db.collection('users').doc(uid).collection('activity');

  @override
  Future<void> record(String uid, ActivityEvent event) async {
    await _activity(uid).add({
      ...event.toJson(),
      'at': Timestamp.fromDate(event.at),
    });
    if (!_pruned) {
      _pruned = true;
      await _prune(uid, before: event.at.subtract(retention));
    }
  }

  /// Once per launch, so the collection cannot grow without bound. Best
  /// effort: a prune that fails leaves old rows, not a missing new one.
  Future<void> _prune(String uid, {required DateTime before}) async {
    try {
      final old = await _activity(uid)
          .where('at', isLessThan: Timestamp.fromDate(before))
          .limit(50)
          .get();
      if (old.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in old.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {
      // Next launch.
    }
  }

  /// The last few things the app noticed about [uid], newest first.
  Stream<List<ActivityEvent>> recent(String uid) => _activity(uid)
      .orderBy('at', descending: true)
      .limit(recentLimit)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) {
            final data = d.data();
            final at = data['at'];
            if (at is! Timestamp) return null;
            return ActivityEvent.fromJson(data, at.toDate());
          })
          .nonNulls
          .toList());
}
