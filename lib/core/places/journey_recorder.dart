/// One journey, recorded as it happens and summarised when it ends.
///
/// The dashboard's Overview and System health read `session_summaries`, and
/// nothing in the app wrote one: `summariseSession` and `publishSummary` had
/// no callers, fixes went under one permanent id, and the only event ever
/// recorded was the destination, under an id used once and thrown away. So
/// Overview said "No sessions yet" for good.
///
/// A session is now a journey: from choosing where to go, to arriving,
/// stopping, signing out, or leaving the app for ten minutes. Its fixes and
/// events share one id, and when it ends its timeline is summarised - counts
/// and durations, no coordinates - and published.
///
/// Everything here needs history consent. Without it nothing is written, and
/// the security rules would refuse it anyway.
///
/// Flutter-free, and behind [JourneyStore], so the throttles and the ending
/// are tested without Firestore.
library;

import '../location/location_fix.dart';
import '../location/location_sharing.dart' show metresBetween;
import 'session_event.dart';
import 'session_summary.dart';
import 'timeline.dart';

/// Where a journey is written, and read back to be summarised.
abstract interface class JourneyStore {
  Future<void> recordFix(String uid, LocationFix fix,
      {required String sessionId});

  Future<void> recordEvent(
    String uid, {
    required String sessionId,
    required SessionEventKind kind,
    String? detail,
  });

  /// The walker left the route. [at] is where, [distanceMetres] is how far.
  Future<void> recordRouteDeviation(
    String uid, {
    required String sessionId,
    required LocationFix at,
    required double distanceMetres,
  });

  Future<SessionTimeline> timeline(String uid, String sessionId);

  Future<void> publishSummary(SessionSummary summary);
}

/// A fix is kept once the user has moved this far since the last one kept...
const double kJourneyFixMetres = 10;

/// ...or this long has passed.
const Duration kJourneyFixInterval = Duration(seconds: 10);

/// The same object is recorded at most once in this long. A person standing
/// by a parked car would otherwise log it every frame.
const Duration kJourneyEventRepeat = Duration(minutes: 1);

/// Left in the background this long, a journey is over.
const Duration kJourneyIdleEnd = Duration(minutes: 10);

class JourneyRecorder {
  JourneyRecorder({required this.store, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final JourneyStore store;
  final DateTime Function() _now;

  String? _uid;
  String? _sessionId;
  List<String> _placeLabels = const [];

  LocationFix? _lastKept;
  DateTime? _lastKeptAt;
  final _lastEvent = <String, DateTime>{};

  /// The journey being recorded, if one is.
  String? get sessionId => _sessionId;

  bool get recording => _sessionId != null;

  /// Starts a journey to [destination] for [uid]. Ends one already running
  /// first.
  ///
  /// [savedLabel] is the name the user gave the place, when it is one of
  /// theirs: the only kind of place name a summary may carry. A place found
  /// by search is not named in it.
  Future<void> start({
    required String uid,
    required bool consent,
    required String destination,
    String? savedLabel,
  }) async {
    await end();
    if (!consent) return;
    final id = 'journey-${_now().millisecondsSinceEpoch}';
    _uid = uid;
    _sessionId = id;
    _placeLabels = [
      if (savedLabel != null && savedLabel.trim().isNotEmpty) savedLabel.trim(),
    ];
    _lastKept = null;
    _lastKeptAt = null;
    _lastEvent.clear();
    await _quietly(() => store.recordEvent(uid,
        sessionId: id,
        kind: SessionEventKind.destinationSet,
        detail: destination));
  }

  /// A position while walking. Kept every [kJourneyFixMetres] or
  /// [kJourneyFixInterval], whichever comes first.
  Future<void> recordFix(LocationFix fix) async {
    final uid = _uid;
    final id = _sessionId;
    if (uid == null || id == null) return;
    final last = _lastKept;
    final lastAt = _lastKeptAt;
    final now = _now();
    if (last != null &&
        lastAt != null &&
        now.difference(lastAt) < kJourneyFixInterval &&
        metresBetween(last, fix) < kJourneyFixMetres) {
      return;
    }
    _lastKept = fix;
    _lastKeptAt = now;
    await _quietly(() => store.recordFix(uid, fix, sessionId: id));
  }

  /// Something that happened on the way. [key] names what it was about -
  /// the object warned of - so the same one is recorded at most once in
  /// [kJourneyEventRepeat]; with no key every one is kept.
  Future<void> recordEvent(SessionEventKind kind,
      {String? detail, String? key}) async {
    final uid = _uid;
    final id = _sessionId;
    if (uid == null || id == null) return;
    if (key != null) {
      final seen = '${kind.name}:$key';
      final now = _now();
      final last = _lastEvent[seen];
      if (last != null && now.difference(last) < kJourneyEventRepeat) return;
      _lastEvent[seen] = now;
    }
    await _quietly(() =>
        store.recordEvent(uid, sessionId: id, kind: kind, detail: detail));
  }

  /// The off-route check tripped. Nothing is written without a journey, and
  /// a refused write does not stop the directions. Not throttled: the guide
  /// calls this once per time the check trips.
  Future<void> recordRouteDeviation(LocationFix at,
      {required double distanceMetres}) async {
    final uid = _uid;
    final id = _sessionId;
    if (uid == null || id == null) return;
    await _quietly(() => store.recordRouteDeviation(
          uid,
          sessionId: id,
          at: at,
          distanceMetres: distanceMetres,
        ));
  }

  /// Ends the journey and publishes its summary. Nothing happens when none
  /// is running, so every way out can call it.
  Future<void> end() async {
    final uid = _uid;
    final id = _sessionId;
    final labels = _placeLabels;
    _uid = null;
    _sessionId = null;
    _placeLabels = const [];
    if (uid == null || id == null) return;
    await _quietly(() async {
      final timeline = await store.timeline(uid, id);
      await store.publishSummary(
          summariseSession(timeline, userId: uid, placeLabels: labels));
    });
  }

  /// Recording is never why directions or an SOS fail: no connection, or
  /// consent withdrawn mid-journey, and the rules refuse. The journey goes
  /// on without its record.
  static Future<void> _quietly(Future<void> Function() write) async {
    try {
      await write();
    } catch (_) {}
  }
}
