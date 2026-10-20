import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/navigation/destination.dart';
import '../core/navigation/navigation_history.dart';

/// Where a trip is written, so the session can be tested without Firestore.
abstract interface class NavigationHistorySink {
  String newId(String uid);

  Future<void> start({
    required String uid,
    required String entryId,
    required Destination destination,
    required double originLat,
    required double originLng,
  });

  Future<void> finish({
    required String uid,
    required String entryId,
    required String status,
  });
}

/// One page of a guardian's query: the trips that parsed, and how many
/// documents the query actually returned (so "load more" knows to ask again).
class NavigationHistoryPage {
  const NavigationHistoryPage({required this.entries, required this.fetched});

  final List<NavigationEntry> entries;
  final int fetched;
}

/// `navigation_history/{uid}/entries/{entryId}`.
///
/// Two ways an old trip disappears. The guardian query only asks for trips
/// whose [startedAt] is inside the last 30 days, so anything older is never
/// shown. [expiresAt] is `startedAt` plus 30 days, for a Firestore time-to-live
/// policy on the `entries` collection group — that policy is switched on in
/// the Cloud console, not from here. [deleteExpired] is the fallback: when
/// the user's app opens it deletes their own expired rows, a batch at a time,
/// in case the policy has not caught up.
///
/// Writes are caught by the caller. A failure here must not stop directions.
class NavigationHistoryRepository implements NavigationHistorySink {
  NavigationHistoryRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _entries(String uid) =>
      _db.collection('navigation_history').doc(uid).collection('entries');

  @override
  String newId(String uid) => _entries(uid).doc().id;

  @override
  Future<void> start({
    required String uid,
    required String entryId,
    required Destination destination,
    required double originLat,
    required double originLng,
  }) {
    final name = _clip(destination.label, 300);
    return _entries(uid).doc(entryId).set({
      'destinationName': name.isEmpty ? 'Destination' : name,
      'destinationAddress': _clip(destination.address, 300),
      'destinationLat': destination.latitude,
      'destinationLng': destination.longitude,
      'originLat': originLat,
      'originLng': originLng,
      'startedAt': FieldValue.serverTimestamp(),
      'endedAt': null,
      'status': NavigationStatus.ongoing.name,
      // Device clock, inside the rules' 29-to-31-day window of server time.
      // The field TTL compares is this one, not startedAt.
      'expiresAt': Timestamp.fromDate(
        DateTime.now().toUtc().add(kNavigationRetention),
      ),
    });
  }

  @override
  Future<void> finish({
    required String uid,
    required String entryId,
    required String status,
  }) {
    return _entries(uid).doc(entryId).update({
      'status': status,
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The paired user's trips since [since], newest first, at most [limit].
  Stream<NavigationHistoryPage> watch({
    required String uid,
    required DateTime since,
    required int limit,
  }) {
    return _entries(uid)
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('startedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
          final entries = <NavigationEntry>[];
          for (final doc in snap.docs) {
            final entry = NavigationEntry.tryParse(doc.id, _dates(doc.data()));
            if (entry != null) entries.add(entry);
          }
          return NavigationHistoryPage(
            entries: entries,
            fetched: snap.docs.length,
          );
        });
  }

  /// One trip, for the map opened from the list.
  Future<NavigationEntry?> read(String uid, String entryId) async {
    final doc = await _entries(uid).doc(entryId).get();
    final data = doc.data();
    if (data == null) return null;
    return NavigationEntry.tryParse(doc.id, _dates(data));
  }

  /// Deletes this user's expired trips. At most 400 per call — Firestore's
  /// batch cap is 500 — and the next launch takes the next batch. Never throws.
  Future<int> deleteExpired(String uid) async {
    try {
      final page = await _entries(uid)
          .where('expiresAt', isLessThan: Timestamp.fromDate(DateTime.now()))
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
      debugPrint('navigation history cleanup failed: $e');
      return 0;
    }
  }

  /// Timestamps become [DateTime]s so the model stays free of Firestore.
  static Map<String, dynamic> _dates(Map<String, dynamic> data) {
    DateTime? at(Object? value) => value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : null;
    return {
      ...data,
      'startedAt': at(data['startedAt']),
      'endedAt': at(data['endedAt']),
      'expiresAt': at(data['expiresAt']),
    };
  }

  static String _clip(String value, int max) {
    final trimmed = value.trim();
    if (trimmed.length <= max) return trimmed;
    return trimmed.substring(0, max);
  }
}
