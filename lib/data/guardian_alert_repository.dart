import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/alerts/guardian_alert.dart';
import '../core/location/location_fix.dart';

/// The one write every guardian alert goes through.
abstract interface class GuardianAlertSink {
  Future<void> send({
    required String uid,
    required String kind,
    required String message,
    required DateTime at,
    double? latitude,
    double? longitude,
  });
}

class FirestoreGuardianAlertSink implements GuardianAlertSink {
  FirestoreGuardianAlertSink({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _alerts(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('guardian_alerts');

  @override
  Future<void> send({
    required String uid,
    required String kind,
    required String message,
    required DateTime at,
    double? latitude,
    double? longitude,
  }) {
    final position = latitude == null || longitude == null
        ? null
        : LocationFix(
            latitude: latitude,
            longitude: longitude,
            accuracyMetres: 0,
            at: at,
          );
    return _alerts(uid).add({
      ...guardianAlertFields(kind: kind, message: message, position: position),
      'at': Timestamp.fromDate(at),
    });
  }
}
