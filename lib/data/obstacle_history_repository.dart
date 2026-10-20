import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/guardian/obstacle_event.dart';

/// Where an urgent obstacle is written, so the session can be tested
/// without Firestore.
abstract interface class ObstacleHistorySink {
  Future<void> record(String uid, ObstacleSighting sighting);
}

/// One page of a guardian's query.
class ObstacleHistoryPage {
  const ObstacleHistoryPage({required this.entries, required this.fetched});

  final List<ObstacleSighting> entries;
  final int fetched;
}

/// `users/{uid}/obstacle_events/{eventId}`.
///
/// The guardian asks only for the last [kObstacleRetention]. [deleteExpired]
/// is the cleanup: the user's phone deletes its own older rows, a batch at
/// a time, because Cloud Functions are not deployed. A guardian cannot
/// delete them.
class ObstacleHistoryRepository implements ObstacleHistorySink {
  ObstacleHistoryRepository({FirebaseFirestore? firestore})
      : _firestore = firestore;

  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _events(String uid) =>
      _db.collection('users').doc(uid).collection('obstacle_events');

  @override
  Future<void> record(String uid, ObstacleSighting sighting) {
    return _events(uid).add({
      ...sighting.toJson(),
      'at': Timestamp.fromDate(sighting.at),
    });
  }

  /// Newest first, from [since] inclusive. [limit] is the page size.
  Stream<ObstacleHistoryPage> watch({
    required String uid,
    required DateTime since,
    required int limit,
  }) {
    return _events(uid)
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final entries = <ObstacleSighting>[];
      for (final doc in snap.docs) {
        final sighting = ObstacleSighting.tryParse(doc.id, _dates(doc.data()));
        if (sighting != null) entries.add(sighting);
      }
      return ObstacleHistoryPage(entries: entries, fetched: snap.docs.length);
    });
  }

  /// Deletes this user's rows older than [kObstacleRetention]. At most 400
  /// per call. Never throws. Runs on the user's phone, once per launch.
  Future<int> deleteExpired(String uid, {DateTime? now}) async {
    try {
      final cutoff = (now ?? DateTime.now()).subtract(kObstacleRetention);
      final page = await _events(uid)
          .where('at', isLessThan: Timestamp.fromDate(cutoff))
          .limit(400)
          .get();
      if (page.docs.isEmpty) return 0;
      final batch = _db.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      return page.docs.length;
    } catch (e) {
      debugPrint('obstacle history cleanup failed: $e');
      return 0;
    }
  }

  static Map<String, dynamic> _dates(Map<String, dynamic> data) {
    final at = data['at'];
    return {
      ...data,
      'at': at is Timestamp
          ? at.toDate()
          : at is DateTime
              ? at
              : null,
    };
  }
}
