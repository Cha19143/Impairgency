import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/location/location_fix.dart';
import '../core/navigation/route_deviation.dart';
import '../core/places/journey.dart';
import '../core/places/place.dart';
import '../core/places/session_event.dart';
import '../core/places/stay.dart';
import '../core/places/timeline.dart';

/// The one collection four requirements are built on.
///
/// §2.B.2 environment learning, §2.B.1 routine learning, §2.A.7 travel
/// recording and §1.3 frequently-visited locations are all aggregations over
/// these rows. No model, no training, one schema.
///
/// Writes are gated on `consent.history` by the security rules as well as here.
/// The check in this class is for a clear message; the rule is what decides.
class LocationHistoryRepository {
  LocationHistoryRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// How long history is kept before [pruneOlderThan] removes it.
  ///
  /// §7 asks for personal data to be protected. The cheapest protection is not
  /// holding it: a year of somebody's movements is a far bigger loss if it
  /// leaks than a fortnight of it, and the learning features work on a
  /// fortnight.
  static const Duration retention = Duration(days: 60);

  CollectionReference<Map<String, dynamic>> _fixes(String uid) =>
      _db.collection('location_history').doc(uid).collection('fixes');

  CollectionReference<Map<String, dynamic>> _events(String uid) =>
      _db.collection('location_history').doc(uid).collection('events');

  /// Records one reading against a session.
  ///
  /// Vague readings are dropped here rather than stored and filtered later.
  /// A 2 km "position" has no use downstream and is still personal data.
  Future<void> record(
    String uid,
    LocationFix fix, {
    required String sessionId,
  }) async {
    if (fix.accuracyMetres > kMaxUsefulAccuracyMetres) return;
    await _fixes(uid).add({
      ...fix.toJson(),
      'at': Timestamp.fromDate(fix.at),
      'sessionId': sessionId,
    });
  }

  /// Records something the app noticed — §2.A.7, and the source of the §1.1
  /// review timeline.
  Future<void> recordEvent(
    String uid, {
    required String sessionId,
    required SessionEventKind kind,
    String? detail,
    LocationFix? at,
  }) async {
    await _events(uid).add({
      'sessionId': sessionId,
      'kind': kind.name,
      if (detail != null) 'detail': detail,
      if (at != null) ...{
        'lat': at.latitude,
        'lng': at.longitude,
      },
      'at': Timestamp.fromDate(at?.at ?? DateTime.now()),
    });
  }

  /// The walker left the route. Same collection as other session events, so
  /// the existing owner-and-consent create rule covers it. [at] is the
  /// position and the timestamp.
  Future<void> recordRouteDeviation(
    String uid, {
    required String sessionId,
    required LocationFix at,
    required double distanceMetres,
  }) async {
    final deviation = RouteDeviation(
      at: at.at,
      latitude: at.latitude,
      longitude: at.longitude,
      distanceMetres: distanceMetres,
    );
    await _events(uid).add({
      ...deviation.documentFields(sessionId: sessionId),
      'at': Timestamp.fromDate(deviation.at),
    });
  }

  Future<List<SessionEvent>> eventsForSession(
      String uid, String sessionId) async {
    final snap = await _events(uid)
        .where('sessionId', isEqualTo: sessionId)
        .orderBy('at')
        .get();
    return snap.docs.map(_toEvent).toList();
  }

  /// The review a §1.1 administrator opens instead of a video player.
  Future<SessionTimeline> timeline(String uid, String sessionId) async {
    final results = await Future.wait([
      journey(uid, sessionId),
      eventsForSession(uid, sessionId),
    ]);
    return buildTimeline(
      results[0] as Journey,
      results[1] as List<SessionEvent>,
    );
  }

  /// Everything recorded in one session, for a replay — §2.A.7.
  Future<Journey> journey(String uid, String sessionId) async {
    final snap = await _fixes(uid)
        .where('sessionId', isEqualTo: sessionId)
        .orderBy('at')
        .get();
    return journeyFrom(sessionId, snap.docs.map(_toFix).toList());
  }

  /// The window the place and routine aggregations read.
  Future<List<LocationFix>> recent(String uid, {DateTime? since}) async {
    final from = since ?? DateTime.now().subtract(retention);
    final snap = await _fixes(uid)
        .where('at', isGreaterThan: Timestamp.fromDate(from))
        .orderBy('at')
        .get();
    return snap.docs.map(_toFix).toList();
  }

  /// As [recent], but carrying each row's session id.
  ///
  /// Separate from [recent] because a `LocationFix` deliberately knows nothing
  /// about storage - it is the type the SOS policy reasons about, and an SOS
  /// fix has no session.
  Future<List<({LocationFix fix, String? sessionId})>> _recent(
    String uid, {
    DateTime? since,
  }) async {
    final from = since ?? DateTime.now().subtract(retention);
    final snap = await _fixes(uid)
        .where('at', isGreaterThan: Timestamp.fromDate(from))
        .orderBy('at')
        .get();
    return snap.docs.map(_toRow).toList();
  }

  /// Places the user returns to — §2.B.2, and §1.3's dashboard panel.
  ///
  /// Derived on read rather than stored. Storing them would mean a second thing
  /// to keep in step with the fixes, and a second thing to delete when the user
  /// asks to be forgotten.
  Future<List<Place>> places(String uid, {DateTime? since}) async =>
      clusterIntoPlaces(detectStays(await recent(uid, since: since)));

  /// Distinct session ids in the window, newest first.
  Future<List<String>> sessions(String uid, {DateTime? since}) async {
    final rows = await _recent(uid, since: since);
    final seen = <String>{};
    for (final row in rows.reversed) {
      final id = row.sessionId;
      if (id != null) seen.add(id);
    }
    return seen.toList();
  }

  /// Forgets everything. Backs "what the app has learned" — §2.B.
  ///
  /// Deletes in batches because a user with two months of history has thousands
  /// of rows and Firestore caps a batch at 500.
  Future<int> forgetAll(String uid) async {
    var deleted = 0;
    // Events as well as fixes. Forgetting where someone went while keeping a
    // log of what they walked past would not be forgetting.
    for (final collection in [_fixes(uid), _events(uid)]) {
      while (true) {
        final page = await collection.limit(400).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        deleted += page.docs.length;
      }
    }
    return deleted;
  }

  /// Forgets one place, by deleting the readings that produced it.
  ///
  /// Places are derived, so there is nothing else to remove — which is the
  /// point of deriving them.
  Future<int> forgetPlace(String uid, Place place) async {
    var deleted = 0;
    for (final visit in place.visits) {
      final page = await _fixes(uid)
          .where('at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(visit.arrived))
          .where('at', isLessThanOrEqualTo: Timestamp.fromDate(visit.departed))
          .get();
      if (page.docs.isEmpty) continue;
      final batch = _db.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += page.docs.length;
    }
    return deleted;
  }

  /// Drops history past [retention]. Called on app start; cheap and idempotent.
  Future<int> pruneOlderThan(String uid, {Duration? age}) async {
    final cutoff = DateTime.now().subtract(age ?? retention);
    final page = await _fixes(uid)
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
  }

  static SessionEvent _toEvent(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return SessionEvent(
      id: doc.id,
      sessionId: data['sessionId'] as String? ?? '',
      at: (data['at'] as Timestamp).toDate(),
      kind: SessionEventKind.values.firstWhere(
        (k) => k.name == data['kind'],
        orElse: () => SessionEventKind.guidanceGiven,
      ),
      detail: data['detail'] as String?,
      latitude: (data['lat'] as num?)?.toDouble(),
      longitude: (data['lng'] as num?)?.toDouble(),
    );
  }

  static ({LocationFix fix, String? sessionId}) _toRow(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return (
      fix: LocationFix(
        latitude: (data['lat'] as num).toDouble(),
        longitude: (data['lng'] as num).toDouble(),
        accuracyMetres: (data['accuracy'] as num?)?.toDouble() ?? 0,
        at: (data['at'] as Timestamp).toDate(),
      ),
      sessionId: data['sessionId'] as String?,
    );
  }

  static LocationFix _toFix(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      _toRow(doc).fix;
}
