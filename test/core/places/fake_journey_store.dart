import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/route_deviation.dart';
import 'package:impairgency/core/places/journey.dart';
import 'package:impairgency/core/places/journey_recorder.dart';
import 'package:impairgency/core/places/session_event.dart';
import 'package:impairgency/core/places/session_summary.dart';
import 'package:impairgency/core/places/timeline.dart';

/// A journey store in memory, whose timelines are built the way the real
/// one's are.
class FakeJourneyStore implements JourneyStore {
  FakeJourneyStore({this.fails = false});

  /// Every write refuses, as the rules do without consent.
  bool fails;

  final fixes = <(String uid, String sessionId, LocationFix fix)>[];
  final events = <(String uid, SessionEvent event)>[];
  final deviations = <(String uid, String sessionId, RouteDeviation deviation)>[];
  final published = <SessionSummary>[];

  DateTime Function() now = DateTime.now;

  void _check() {
    if (fails) throw StateError('permission-denied');
  }

  @override
  Future<void> recordFix(String uid, LocationFix fix,
      {required String sessionId}) async {
    _check();
    fixes.add((uid, sessionId, fix));
  }

  @override
  Future<void> recordEvent(
    String uid, {
    required String sessionId,
    required SessionEventKind kind,
    String? detail,
  }) async {
    _check();
    events.add((
      uid,
      SessionEvent(
        id: 'ev${events.length}',
        sessionId: sessionId,
        at: now(),
        kind: kind,
        detail: detail,
      ),
    ));
  }

  @override
  Future<void> recordRouteDeviation(
    String uid, {
    required String sessionId,
    required LocationFix at,
    required double distanceMetres,
  }) async {
    _check();
    final deviation = RouteDeviation(
      at: at.at,
      latitude: at.latitude,
      longitude: at.longitude,
      distanceMetres: distanceMetres,
    );
    deviations.add((uid, sessionId, deviation));
    events.add((
      uid,
      SessionEvent(
        id: 'ev${events.length}',
        sessionId: sessionId,
        at: at.at,
        kind: SessionEventKind.routeDeviation,
        detail: deviation.documentFields(sessionId: sessionId)['detail']
            as String?,
        latitude: at.latitude,
        longitude: at.longitude,
      ),
    ));
  }

  @override
  Future<SessionTimeline> timeline(String uid, String sessionId) async {
    _check();
    return buildTimeline(
      journeyFrom(sessionId, [
        for (final f in fixes)
          if (f.$1 == uid && f.$2 == sessionId) f.$3,
      ]),
      [
        for (final e in events)
          if (e.$1 == uid && e.$2.sessionId == sessionId) e.$2,
      ],
    );
  }

  @override
  Future<void> publishSummary(SessionSummary summary) async {
    _check();
    published.add(summary);
  }

  List<SessionEventKind> kindsIn(String sessionId) => [
        for (final e in events)
          if (e.$2.sessionId == sessionId) e.$2.kind,
      ];
}
