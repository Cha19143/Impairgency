import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/location/location_fix.dart';
import '../core/location/location_sharing.dart';
import '../core/location/location_source.dart';

/// Where the guardian-facing position goes.
///
/// One field on the user's own document, overwritten each time: `lastFix`.
/// Not the history collection, because "Share where I am" and "Remember
/// where I have been" are two consents. A guardian who may see where the
/// user is now has not been granted a trail of where they were, and one
/// field cannot become a trail.
abstract interface class LastFixSink {
  Future<void> publish(String uid, LocationFix fix);

  /// Removes the field. Called when sharing is switched off, so a guardian's
  /// card goes back to "not sharing" rather than showing a stale point.
  Future<void> clear(String uid);
}

class FirestoreLastFixSink implements LastFixSink {
  FirestoreLastFixSink({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<void> publish(String uid, LocationFix fix) =>
      _db.collection('users').doc(uid).update({
        'lastFix': {
          'lat': fix.latitude,
          'lng': fix.longitude,
          'accuracy': fix.accuracyMetres,
          'at': Timestamp.fromDate(fix.at),
        },
      });

  @override
  Future<void> clear(String uid) => _db
      .collection('users')
      .doc(uid)
      .update({'lastFix': FieldValue.delete()});
}

/// What the session drives. The real one below; tests hand in a recorder.
abstract interface class LocationSharing {
  bool get isSharing;

  /// Starts, or keeps going with the new settings if already started.
  void start(String uid, {required bool recordHistory});

  void stop();

  /// Removes what has been published, for when consent is withdrawn.
  Future<void> forget(String uid);
}

/// Publishes the user's position while the app is open and sharing is on.
///
/// Polls rather than streams: a reading every [interval] is all a guardian's
/// card needs, it is a fraction of the battery of a continuous stream, and
/// it works against the same [LocationSource] SOS and "where am I" use. The
/// [SharePolicy] then decides which readings are worth a write.
///
/// Nothing here runs in the background. When the app is put away the session
/// stops this, and the guardian's card ages honestly - "12 minutes ago" -
/// rather than the app pretending to a position it is no longer reading.
class LocationSharer implements LocationSharing {
  LocationSharer({
    required LocationSource source,
    required LastFixSink sink,
    Future<void> Function(String uid, LocationFix fix)? recordHistory,
    SharePolicy policy = const SharePolicy(),
    Duration interval = const Duration(seconds: 30),
    Duration fixTimeout = const Duration(seconds: 10),
    DateTime Function() now = DateTime.now,
  })  : _source = source,
        _sink = sink,
        _recordHistory = recordHistory,
        _policy = policy,
        _interval = interval,
        _fixTimeout = fixTimeout,
        _now = now;

  final LocationSource _source;
  final LastFixSink _sink;
  final Future<void> Function(String uid, LocationFix fix)? _recordHistory;
  final SharePolicy _policy;
  final Duration _interval;
  final Duration _fixTimeout;
  final DateTime Function() _now;

  String? _uid;
  bool _history = false;
  Timer? _timer;
  bool _polling = false;

  /// Whether the OS has been asked this session. Consent is the app's
  /// question; the permission is the platform's, and nothing else in the
  /// user's path asks it - only "where am I" and directions do - so someone
  /// who switched sharing on and used neither would never be asked, and
  /// never share. Asked once per start, never again if declined for good.
  bool _askedPermission = false;

  /// The last reading that reached the server, for the policy. Not the last
  /// reading taken: a write that failed offline must be tried again with the
  /// next reading, not skipped because "nothing moved since".
  LocationFix? _published;

  @override
  bool get isSharing => _uid != null;

  @override
  void start(String uid, {required bool recordHistory}) {
    if (_uid == uid) {
      _history = recordHistory;
      return;
    }
    stop();
    _uid = uid;
    _history = recordHistory;
    _published = null;
    _askedPermission = false;
    _timer = Timer.periodic(_interval, (_) => unawaited(poll()));
    unawaited(poll());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _uid = null;
    _published = null;
  }

  @override
  Future<void> forget(String uid) async {
    try {
      await _sink.clear(uid);
    } catch (e) {
      debugPrint('Could not clear the shared location: $e');
    }
  }

  /// One reading, one decision, at most one write. Public so a test can
  /// drive it without a clock.
  Future<void> poll() async {
    final uid = _uid;
    if (uid == null || _polling) return;
    _polling = true;
    try {
      var availability = await _source.availability();
      if (availability == LocationAvailability.denied && !_askedPermission) {
        _askedPermission = true;
        availability = await _source.requestPermission();
      }
      if (availability != LocationAvailability.ready) return;
      final fix = await _source.currentFix(timeout: _fixTimeout);
      if (fix == null || _uid != uid) return;
      if (!_policy.shouldPublish(last: _published, next: fix, now: _now())) {
        return;
      }
      await _sink.publish(uid, fix);
      _published = fix;
      if (_history) {
        try {
          await _recordHistory?.call(uid, fix);
        } catch (e) {
          // The guardian has the point; the trail is the lesser loss.
          debugPrint('Could not record location history: $e');
        }
      }
    } catch (e) {
      // Offline, or the rules said no. The next poll tries again.
      debugPrint('Could not share location: $e');
    } finally {
      _polling = false;
    }
  }
}
