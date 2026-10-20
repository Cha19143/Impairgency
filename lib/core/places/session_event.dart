/// Things worth recording about a session, other than where it went.
library;

enum SessionEventKind {
  obstacleDetected,
  stairsDetected,
  textRead,
  guidanceGiven,
  sosArmed,
  sosFired,
  sosCancelled,
  placeLearned,

  /// The user said where they were going before they left - §2.A.7's
  /// travel recording, with a destination on it.
  destinationSet,

  /// The walker left the route. Same moment as the existing off-route
  /// detection. A later step can notify a guardian from this, without
  /// another detector.
  routeDeviation,
}

class SessionEvent {
  const SessionEvent({
    required this.id,
    required this.sessionId,
    required this.at,
    required this.kind,
    this.detail,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String sessionId;
  final DateTime at;
  final SessionEventKind kind;

  /// What was detected or read: "chair", "medicine bottle".
  final String? detail;

  final double? latitude;
  final double? longitude;

  bool get hasPosition => latitude != null && longitude != null;

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'kind': kind.name,
        if (detail != null) 'detail': detail,
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
      };
}

/// How much an event should stand out to someone scanning a session.
enum EventWeight {
  /// Routine. The app doing its job.
  ordinary,

  /// A hazard the user was warned about.
  hazard,

  /// An emergency, or an emergency that turned out not to be one.
  emergency,
}

EventWeight weightOf(SessionEventKind kind) => switch (kind) {
      SessionEventKind.stairsDetected => EventWeight.hazard,
      SessionEventKind.sosArmed ||
      SessionEventKind.sosFired ||
      SessionEventKind.sosCancelled =>
        EventWeight.emergency,
      _ => EventWeight.ordinary,
    };

/// Plain description of one event.
String describeEvent(SessionEvent event) {
  final detail = event.detail;
  return switch (event.kind) {
    SessionEventKind.obstacleDetected =>
      detail == null ? 'Obstacle detected' : 'Obstacle detected — $detail',
    SessionEventKind.stairsDetected =>
      detail == null ? 'Stairs detected' : 'Stairs detected — $detail',
    SessionEventKind.textRead =>
      detail == null ? 'Text read aloud' : 'Text read — $detail',
    SessionEventKind.guidanceGiven =>
      detail == null ? 'Guidance given' : 'Guidance — $detail',
    SessionEventKind.sosArmed => 'SOS armed, counting down',
    SessionEventKind.sosFired => 'SOS sent',
    SessionEventKind.sosCancelled =>
      detail == null ? 'SOS cancelled' : 'SOS cancelled — $detail',
    SessionEventKind.placeLearned =>
      detail == null ? 'Place recognised' : 'Place recognised — $detail',
    SessionEventKind.destinationSet =>
      detail == null ? 'Destination set' : 'Heading for $detail',
    SessionEventKind.routeDeviation =>
      detail == null ? 'Left the route' : 'Left the route — $detail',
  };
}
