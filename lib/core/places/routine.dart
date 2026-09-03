/// When someone tends to be somewhere.
///
/// §2.B.1 asks the AI to "gradually learn the user's regular routines... usual
/// travel schedules or patterns". This does it by counting, and — the part that
/// matters — it refuses to claim a pattern it cannot support. Two visits is not
/// a routine, and a place someone turns up at any old hour has no typical time
/// however many visits it has.
///
/// The app says "you usually leave around half past seven". It never says "the
/// AI has learned your routine", because it has not learned anything; it has
/// counted something.
library;

import 'place.dart';

/// Below this, there is no pattern to speak of, only a coincidence.
const int kMinVisitsForRoutine = 4;

/// If the middle half of arrivals is spread wider than this, there is no
/// typical time and the app says so instead of averaging to a fiction.
const Duration kMaxTypicalSpread = Duration(minutes: 90);

class Routine {
  const Routine({
    required this.visitCount,
    required this.weekdays,
    this.typicalArrival,
    this.typicalDeparture,
  });

  final int visitCount;

  /// ISO weekdays seen, 1 = Monday.
  final Set<int> weekdays;

  /// Median arrival, as minutes past local midnight. Null when arrivals are too
  /// scattered to have a typical one.
  final int? typicalArrival;

  final int? typicalDeparture;

  bool get hasTypicalTime => typicalArrival != null;

  /// Every visit fell Monday to Friday, and there are enough of them to mean it.
  bool get isWorkweekPattern =>
      weekdays.isNotEmpty && weekdays.every((d) => d <= 5) && visitCount >= 5;

  bool get isWeekendPattern =>
      weekdays.isNotEmpty && weekdays.every((d) => d >= 6) && visitCount >= 3;
}

/// Reads a place's visits for a pattern.
///
/// [offset] shifts stored UTC timestamps to the user's local time; a routine
/// described in UTC would be wrong by hours and confidently so.
Routine? routineOf(
  Place place, {
  Duration offset = Duration.zero,
  int minVisits = kMinVisitsForRoutine,
}) {
  if (place.visitCount < minVisits) return null;

  final arrivals = <int>[];
  final departures = <int>[];
  final weekdays = <int>{};

  for (final visit in place.visits) {
    final arrived = visit.arrived.toUtc().add(offset);
    final departed = visit.departed.toUtc().add(offset);
    arrivals.add(arrived.hour * 60 + arrived.minute);
    departures.add(departed.hour * 60 + departed.minute);
    weekdays.add(arrived.weekday);
  }

  return Routine(
    visitCount: place.visitCount,
    weekdays: weekdays,
    typicalArrival: _typical(arrivals),
    typicalDeparture: _typical(departures),
  );
}

/// Median, but only if the middle half of the values agree.
///
/// The median alone would happily report a typical arrival of 1pm for someone
/// who turns up at 7am and 7pm. The spread check is what stops that.
int? _typical(List<int> minutes) {
  if (minutes.length < 2) return null;
  final sorted = [...minutes]..sort();

  final lower = sorted[(sorted.length * 0.25).floor()];
  final upper = sorted[((sorted.length * 0.75).ceil() - 1).clamp(0, sorted.length - 1)];
  if (upper - lower > kMaxTypicalSpread.inMinutes) return null;

  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : ((sorted[mid - 1] + sorted[mid]) / 2).round();
}

/// Minutes past midnight, said the way a person would say it.
String clockTime(int minutesPastMidnight) {
  final h24 = (minutesPastMidnight ~/ 60) % 24;
  final m = minutesPastMidnight % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final period = h24 < 12 ? 'in the morning' : (h24 < 18 ? 'in the afternoon' : 'in the evening');
  final minutes = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
  return '$h12$minutes $period';
}

/// What the app tells the user about a place, or null if it has nothing
/// trustworthy to say.
///
/// Phrased as observation, not insight. "You usually arrive around eight in the
/// morning" is a countable claim the user can check and correct. "We predict
/// your schedule" is not.
String? describeRoutine(Place place, {Duration offset = Duration.zero}) {
  final routine = routineOf(place, offset: offset);
  if (routine == null) return null;

  final where = place.label ?? 'here';
  final when = routine.isWorkweekPattern
      ? ', on weekdays'
      : (routine.isWeekendPattern ? ', at weekends' : '');

  if (!routine.hasTypicalTime) {
    return 'You have been $where ${routine.visitCount} times$when, '
        'but not at a regular time.';
  }

  final arrival = clockTime(routine.typicalArrival!);
  final departure = routine.typicalDeparture == null
      ? ''
      : ' and leave around ${clockTime(routine.typicalDeparture!)}';
  return 'You usually arrive $where around $arrival$departure$when. '
      '${routine.visitCount} visits so far.';
}
