import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/alerts/sos_alert.dart';

/// Reads and writes emergency events.
class SosRepository {
  SosRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Firestore's `whereIn` ceiling. A guardian watching more than this is
  /// outside anything this project targets, but it is bounded rather than
  /// silently truncated - see [watchFor].
  static const int maxWatchedPerQuery = 30;

  CollectionReference<Map<String, dynamic>> get _events =>
      _db.collection('sos_events');

  /// Live events for the users this guardian is paired with.
  ///
  /// Bounded by [kAlertableAge] in the query as well as in [shouldAlert]. The
  /// second check is what actually decides; this one keeps a guardian who has
  /// been paired for a year from downloading a year of history every launch.
  Stream<List<SosEvent>> watchFor(List<String> viUserIds, {DateTime? since}) {
    if (viUserIds.isEmpty) return Stream.value(const []);
    if (viUserIds.length > maxWatchedPerQuery) {
      throw ArgumentError(
        'Watching ${viUserIds.length} users needs more than one query; '
        'Firestore whereIn allows $maxWatchedPerQuery.',
      );
    }
    final from = since ?? DateTime.now().subtract(kAlertableAge);
    return _events
        .where('userId', whereIn: viUserIds)
        .where('at', isGreaterThan: Timestamp.fromDate(from))
        .snapshots()
        .map((snap) => snap.docs.map(_toEvent).toList());
  }

  static SosEvent _toEvent(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return SosEvent(
      id: doc.id,
      userId: data['userId'] as String,
      at: (data['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      locationSummary: data['locationSummary'] as String?,
      cancelled: data['cancelled'] == true,
    );
  }
}
