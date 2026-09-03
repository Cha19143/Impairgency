/// The event timeline that stands in for video review.
///
/// §1.1 asks administrators to review recorded sessions "to analyse navigation
/// performance and identify possible system improvements". That is the stated
/// purpose; video is only the stated means. A timeline of what the app detected
/// and what the user did answers the same question — and it costs no storage
/// and carries none of the consent burden of recording a blind person's home.
///
/// The part that actually serves the requirement is [SessionTimeline.concerns].
/// A list of events tells an administrator what happened; the concerns tell
/// them where the system let the user down, which is what §1.1 is asking for.
library;

import 'journey.dart';
import 'session_event.dart';

class TimelineRow {
  const TimelineRow({
    required this.elapsed,
    required this.event,
    required this.text,
    required this.weight,
  });

  /// Time since the session began, which is how a reviewer reads a session.
  final Duration elapsed;

  final SessionEvent event;
  final String text;
  final EventWeight weight;

  /// `mm:ss`, or `h:mm:ss` past the hour.
  String get stamp {
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class SessionTimeline {
  const SessionTimeline({
    required this.journey,
    required this.rows,
    required this.summary,
    required this.concerns,
  });

  final Journey journey;
  final List<TimelineRow> rows;

  /// One line an administrator reads before deciding whether to look closer.
  final String summary;

  /// What a reviewer should actually look at. Empty is the good case.
  final List<String> concerns;

  bool get needsAttention => concerns.isNotEmpty;
}

/// A session with this much of its trace thrown away was recorded somewhere the
/// app could barely position the user, which is itself worth knowing.
const double kHighDiscardFraction = 0.4;

SessionTimeline buildTimeline(Journey journey, List<SessionEvent> events) {
  final ordered = [...events]..sort((a, b) => a.at.compareTo(b.at));
  final origin = journey.startedAt ??
      (ordered.isEmpty ? null : ordered.first.at);

  final rows = ordered
      .map((e) => TimelineRow(
            elapsed: origin == null ? Duration.zero : e.at.difference(origin),
            event: e,
            text: describeEvent(e),
            weight: weightOf(e.kind),
          ))
      .toList();

  return SessionTimeline(
    journey: journey,
    rows: rows,
    summary: _summarise(journey, ordered),
    concerns: _concerns(journey, ordered),
  );
}

String _summarise(Journey journey, List<SessionEvent> events) {
  final parts = <String>[];

  if (journey.duration > Duration.zero) {
    final m = journey.duration.inMinutes;
    parts.add(m < 1 ? 'under a minute' : '$m min');
  }
  if (journey.metresTravelled > 0) {
    parts.add(describeDistance(journey.metresTravelled));
  }
  parts.add(events.length == 1 ? '1 event' : '${events.length} events');

  final sos = events.where((e) => e.kind == SessionEventKind.sosFired).length;
  if (sos > 0) parts.add(sos == 1 ? '1 SOS' : '$sos SOS');

  return parts.join(' · ');
}

List<String> _concerns(Journey journey, List<SessionEvent> events) {
  final concerns = <String>[];

  final cancelled =
      events.where((e) => e.kind == SessionEventKind.sosCancelled).toList();
  final fired = events.where((e) => e.kind == SessionEventKind.sosFired);

  if (cancelled.isNotEmpty) {
    // A cancelled SOS is not a non-event. Either the countdown saved someone
    // from a false alarm - good, and worth knowing how often - or the SOS
    // button is too easy to hit, which is a usability defect.
    concerns.add(cancelled.length == 1
        ? 'An SOS was armed and cancelled. Check whether it was triggered by '
            'accident.'
        : '${cancelled.length} SOS attempts were cancelled. The button may be '
            'too easy to hit by accident.');
  }

  if (fired.isNotEmpty) {
    concerns.add('An SOS was sent during this session.');
  }

  final stairs =
      events.where((e) => e.kind == SessionEventKind.stairsDetected).length;
  if (stairs >= 3) {
    concerns.add('Stairs were detected $stairs times. Worth checking the '
        'warnings were early enough to be useful.');
  }

  final total = journey.path.length + journey.discarded;
  if (total > 0 && journey.discarded / total >= kHighDiscardFraction) {
    concerns.add('${journey.discarded} of $total readings were unusable. '
        'Positioning was poor here, so guidance may have been too.');
  }

  if (journey.path.length >= 2 &&
      journey.metresTravelled < 20 &&
      journey.duration > const Duration(minutes: 5)) {
    // The app was guiding for minutes and the user did not move. Either they
    // were stationary and the session should not have been running, or they
    // were stuck.
    concerns.add('The session ran for ${journey.duration.inMinutes} minutes '
        'without moving. The user may have been stuck, or the session may not '
        'have ended when it should.');
  }

  return concerns;
}
