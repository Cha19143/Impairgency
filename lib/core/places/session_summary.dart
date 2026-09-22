/// The aggregate an administrator sees, instead of the trace.
///
/// §1.3 wants counts across every user. Doing that over the raw fixes would
/// mean giving administrators a collection-group read of everybody's
/// coordinates — a far bigger grant than the requirement needs, and expensive
/// besides.
///
/// So the client writes one summary per session and administrators read those.
/// It carries durations, distances and counts. **It carries no coordinates at
/// all.** The only place names in it are ones the user typed themselves; the
/// dashboard's "frequently visited locations" panel counts those words, which
/// answers §1.3 without anyone being able to point at a map and say where a
/// blind person lives.
library;

import 'session_event.dart';
import 'timeline.dart';

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.userId,
    required this.startedAt,
    required this.duration,
    required this.metresTravelled,
    required this.eventCounts,
    required this.discardedFraction,
    required this.concernCount,
    this.placeLabels = const [],
  });

  final String sessionId;
  final String userId;
  final DateTime startedAt;
  final Duration duration;
  final double metresTravelled;

  /// How many of each kind of thing happened, keyed by [SessionEventKind.name].
  final Map<String, int> eventCounts;

  /// Share of readings that were unusable. A positioning-quality proxy, and the
  /// closest thing to a truthful signal about guidance quality that exists
  /// without ground truth to compare against.
  final double discardedFraction;

  final int concernCount;

  /// Names the *user* gave places on this route. Never a coordinate, and never
  /// a name the app invented.
  final List<String> placeLabels;

  int countOf(SessionEventKind kind) => eventCounts[kind.name] ?? 0;

  bool get hadEmergency => countOf(SessionEventKind.sosFired) > 0;

  Map<String, Object?> toJson() => {
        'userId': userId,
        'sessionId': sessionId,
        'minutes': duration.inMinutes,
        'metres': metresTravelled.round(),
        'eventCounts': eventCounts,
        'discardedFraction': discardedFraction,
        'concernCount': concernCount,
        'placeLabels': placeLabels,
      };
}

SessionSummary summariseSession(
  SessionTimeline timeline, {
  required String userId,
  List<String> placeLabels = const [],
}) {
  final counts = <String, int>{};
  for (final row in timeline.rows) {
    counts.update(row.event.kind.name, (n) => n + 1, ifAbsent: () => 1);
  }

  final journey = timeline.journey;
  final total = journey.path.length + journey.discarded;

  return SessionSummary(
    sessionId: journey.sessionId,
    userId: userId,
    startedAt: journey.startedAt ?? DateTime.now(),
    duration: journey.duration,
    metresTravelled: journey.metresTravelled,
    eventCounts: counts,
    discardedFraction: total == 0 ? 0 : journey.discarded / total,
    concernCount: timeline.concerns.length,
    placeLabels: placeLabels,
  );
}

/// What §1.3 asks the dashboard to show, computed over many sessions.
class UsageOverview {
  const UsageOverview({
    required this.activeUsers,
    required this.sessions,
    required this.sosIncidents,
    required this.frequentPlaceLabels,
    required this.detectionCounts,
    required this.medianDiscardedFraction,
  });

  final int activeUsers;
  final int sessions;
  final int sosIncidents;

  /// User-typed place names, most common first. §1.3's panel.
  final List<({String label, int count})> frequentPlaceLabels;

  /// Detections by kind, most common first. §1.3's "object and environment
  /// detection performance", as far as it can honestly be measured — see
  /// [detectionCaveat].
  final List<({String kind, int count})> detectionCounts;

  final double medianDiscardedFraction;

  /// Said on the dashboard, next to the numbers.
  ///
  /// The requirement asks for detection *performance*. Performance means
  /// accuracy, accuracy means comparing detections against what was really
  /// there, and nobody has labelled what was really there. Counting detections
  /// and positioning quality is what can be measured; claiming an accuracy
  /// figure would be inventing one.
  static const String detectionCaveat =
      'Counts of what the app reported, not accuracy. Measuring accuracy would '
      'need someone to label what was actually in each scene.';
}

/// [summaries] over one period.
///
/// Journeys are recorded only for users with history turned on, so two
/// numbers come from elsewhere when they are known: [sosIncidents], counted
/// from the SOS records themselves, and [alsoActive], the users who shared a
/// position in the period without a recorded journey.
UsageOverview overviewOf(
  List<SessionSummary> summaries, {
  int? sosIncidents,
  Set<String> alsoActive = const {},
}) {
  if (summaries.isEmpty) {
    return UsageOverview(
      activeUsers: alsoActive.length,
      sessions: 0,
      sosIncidents: sosIncidents ?? 0,
      frequentPlaceLabels: const [],
      detectionCounts: const [],
      medianDiscardedFraction: 0,
    );
  }

  final labels = <String, int>{};
  final detections = <String, int>{};
  var sos = 0;

  for (final s in summaries) {
    for (final label in s.placeLabels) {
      final key = label.trim();
      if (key.isEmpty) continue;
      labels.update(key, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final entry in s.eventCounts.entries) {
      detections.update(entry.key, (n) => n + entry.value,
          ifAbsent: () => entry.value);
    }
    sos += s.countOf(SessionEventKind.sosFired);
  }

  final discards = summaries.map((s) => s.discardedFraction).toList()..sort();

  return UsageOverview(
    activeUsers: {...summaries.map((s) => s.userId), ...alsoActive}.length,
    sessions: summaries.length,
    sosIncidents: sosIncidents ?? sos,
    frequentPlaceLabels: _ranked(labels).map((e) => (label: e.$1, count: e.$2)).toList(),
    detectionCounts: _ranked(detections).map((e) => (kind: e.$1, count: e.$2)).toList(),
    medianDiscardedFraction: discards[discards.length ~/ 2],
  );
}

List<(String, int)> _ranked(Map<String, int> counts) {
  final entries = counts.entries.map((e) => (e.key, e.value)).toList();
  entries.sort((a, b) {
    final byCount = b.$2.compareTo(a.$2);
    return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
  });
  return entries;
}
