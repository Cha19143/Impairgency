import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/alerts/sos_alert.dart';
import '../core/guardian/watched_user.dart';
import '../core/location/location_fix.dart';
import 'pairing_repository.dart';

/// What the guardian dashboard reads.
///
/// Built on the pairing repository and the collections the rules already
/// grant a paired guardian: the user document, the location fixes while
/// consent is on, and the SOS events. Nothing here is new data - the tester
/// asked for a screen, and the screen reads what Phase 1 and 2 put there.
class GuardianRepository {
  GuardianRepository({
    required PairingRepository pairing,
    FirebaseFirestore? firestore,
  })  : _pairing = pairing,
        _firestore = firestore;

  final PairingRepository _pairing;
  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  /// Everything the dashboard shows, kept live.
  ///
  /// One stream per watched user for the profile, one for the latest fix,
  /// and one for recent SOS events; merged so the screen has one thing to
  /// listen to. A guardian watches one or two people, not hundreds.
  Stream<List<WatchedUser>> watch(String guardianId) {
    return _pairing.watchedUsers(guardianId).switchMap((uids) {
      if (uids.isEmpty) return Stream.value(const <WatchedUser>[]);
      return _combine(uids.map(_watchOne).toList());
    });
  }

  Stream<WatchedUser> _watchOne(String uid) {
    final profile = _db.collection('users').doc(uid).snapshots();
    return profile.switchMap((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      final contact = data['emergencyContact'] as Map<String, dynamic>?;
      final consent = data['consent'] as Map<String, dynamic>?;
      final shares = consent?['location'] == true;
      final base = WatchedUser(
        uid: uid,
        name: (data['name'] ?? data['displayName']) as String?,
        phone: data['phone'] as String?,
        contactName: contact?['name'] as String?,
        contactNumber: contact?['number'] as String?,
        sharesLocation: shares,
      );

      // Only asked for when consent says the server will answer. Asking
      // anyway would be a permission error on every snapshot.
      final fixes = shares
          ? _latestFix(uid)
          : Stream<LocationFix?>.value(null);
      final sos = _lastSos(uid);

      return _combine2(fixes, sos).map((pair) => WatchedUser(
            uid: base.uid,
            name: base.name,
            phone: base.phone,
            contactName: base.contactName,
            contactNumber: base.contactNumber,
            sharesLocation: base.sharesLocation,
            fix: pair.$1,
            lastSos: pair.$2,
          ));
    });
  }

  Stream<LocationFix?> _latestFix(String uid) => _db
      .collection('location_history')
      .doc(uid)
      .collection('fixes')
      .orderBy('at', descending: true)
      .limit(1)
      .snapshots()
      .map((snap) {
        if (snap.docs.isEmpty) return null;
        final data = snap.docs.first.data();
        return LocationFix(
          latitude: (data['lat'] as num).toDouble(),
          longitude: (data['lng'] as num).toDouble(),
          accuracyMetres: (data['accuracy'] as num?)?.toDouble() ?? 0,
          at: (data['at'] as Timestamp).toDate(),
        );
      })
      // Consent revoked between the profile read and this query, or a rule
      // this client is not paired for. Not a crash; a line that says so.
      .handleError((_) {}, test: (_) => true)
      .startWithNull();

  Stream<DateTime?> _lastSos(String uid) => recentSosEvents(uid)
      .map((events) {
        final live = events.where((e) => !e.cancelled).toList()
          ..sort((a, b) => b.at.compareTo(a.at));
        return live.isEmpty ? null : live.first.at;
      })
      .handleError((_) {}, test: (_) => true)
      .startWithNull();

  /// SOS events for one user in the last day, newest first.
  ///
  /// Bounded so a listener attaching does not replay every emergency the
  /// user ever had; the watcher bounds it again by [kAlertableAge].
  Stream<List<SosEvent>> recentSosEvents(String uid) => _db
      .collection('sos_events')
      .where('userId', isEqualTo: uid)
      .where('at',
          isGreaterThan: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 24))))
      .orderBy('at', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) {
            final data = d.data();
            return SosEvent(
              id: d.id,
              userId: data['userId'] as String,
              at: (data['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
              locationSummary: data['locationSummary'] as String?,
              cancelled: data['cancelled'] == true,
            );
          }).toList());

  /// Every recent SOS across everyone this guardian watches, for the
  /// watcher that raises the notification.
  Stream<List<SosEvent>> sosFeed(String guardianId) =>
      _pairing.watchedUsers(guardianId).switchMap((uids) {
        if (uids.isEmpty) return Stream.value(const <SosEvent>[]);
        return _combine(uids
                .map((uid) => recentSosEvents(uid)
                    .handleError((_) {}, test: (_) => true))
                .toList())
            .map((lists) => lists.expand((l) => l).toList());
      });
}

/// The latest value from each stream, emitted whenever any of them emits.
///
/// Written here rather than pulling in `rxdart` for one operator.
Stream<List<T>> _combine<T>(List<Stream<T>> streams) {
  late StreamController<List<T>> controller;
  final latest = List<T?>.filled(streams.length, null);
  final seen = List<bool>.filled(streams.length, false);
  final subs = <StreamSubscription<T>>[];

  controller = StreamController<List<T>>(
    onListen: () {
      for (var i = 0; i < streams.length; i++) {
        subs.add(streams[i].listen((value) {
          latest[i] = value;
          seen[i] = true;
          if (seen.every((s) => s)) controller.add(latest.cast<T>().toList());
        }, onError: controller.addError));
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return controller.stream;
}

Stream<(A, B)> _combine2<A, B>(Stream<A> a, Stream<B> b) {
  late StreamController<(A, B)> controller;
  A? la;
  B? lb;
  var seenA = false;
  var seenB = false;
  StreamSubscription<A>? sa;
  StreamSubscription<B>? sb;
  controller = StreamController<(A, B)>(
    onListen: () {
      sa = a.listen((v) {
        la = v;
        seenA = true;
        if (seenB) controller.add((la as A, lb as B));
      }, onError: controller.addError);
      sb = b.listen((v) {
        lb = v;
        seenB = true;
        if (seenA) controller.add((la as A, lb as B));
      }, onError: controller.addError);
    },
    onCancel: () async {
      await sa?.cancel();
      await sb?.cancel();
    },
  );
  return controller.stream;
}

extension _SwitchMap<T> on Stream<T> {
  /// Maps each value to a stream and follows only the latest one.
  Stream<R> switchMap<R>(Stream<R> Function(T value) mapper) {
    late StreamController<R> controller;
    StreamSubscription<T>? outer;
    StreamSubscription<R>? inner;
    controller = StreamController<R>(
      onListen: () {
        outer = listen((value) {
          inner?.cancel();
          inner = mapper(value).listen(controller.add,
              onError: controller.addError);
        }, onError: controller.addError, onDone: () => controller.close());
      },
      onCancel: () async {
        await inner?.cancel();
        await outer?.cancel();
      },
    );
    return controller.stream;
  }
}

extension _StartWithNull<T> on Stream<T?> {
  /// Emits null first, so a combiner waiting on this stream is not held up
  /// by a query that has nothing to say yet.
  Stream<T?> startWithNull() async* {
    yield null;
    yield* this;
  }
}
