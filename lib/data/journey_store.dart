import '../core/location/location_fix.dart';
import '../core/places/journey_recorder.dart';
import '../core/places/session_event.dart';
import '../core/places/session_summary.dart';
import '../core/places/timeline.dart';
import 'admin_repository.dart';
import 'location_history_repository.dart';

/// [JourneyStore] on Firestore: the history collection for the journey, the
/// summaries collection for the dashboard.
///
/// Takes its repositories as getters, so nothing touches Firebase until a
/// journey is actually recorded.
class FirestoreJourneyStore implements JourneyStore {
  FirestoreJourneyStore({
    required LocationHistoryRepository Function() history,
    required AdminRepository Function() admin,
  })  : _history = history,
        _admin = admin;

  final LocationHistoryRepository Function() _history;
  final AdminRepository Function() _admin;

  @override
  Future<void> recordFix(String uid, LocationFix fix,
          {required String sessionId}) =>
      _history().record(uid, fix, sessionId: sessionId);

  @override
  Future<void> recordEvent(
    String uid, {
    required String sessionId,
    required SessionEventKind kind,
    String? detail,
  }) =>
      _history().recordEvent(uid,
          sessionId: sessionId, kind: kind, detail: detail);

  @override
  Future<SessionTimeline> timeline(String uid, String sessionId) =>
      _history().timeline(uid, sessionId);

  @override
  Future<void> publishSummary(SessionSummary summary) =>
      _admin().publishSummary(summary);
}
