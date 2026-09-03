/// One session's path, cleaned up enough to be worth showing.
///
/// §2.A.7 asks the app to record travel so a user can review their journeys and
/// so the app can learn common routes. Both need a path that is not mostly
/// noise: a raw GPS trace contains readings that teleport a kilometre and back,
/// and a distance total built from those is nonsense.
library;

import '../location/location_fix.dart';
import 'geo.dart';

/// A reading vaguer than this is a cell-tower guess. It goes in the record but
/// not in the path.
const double kMaxUsefulAccuracyMetres = 200;

/// Above this implied speed, a segment is a GPS artefact rather than travel.
///
/// 55 m/s is about 200 km/h. Nobody this app is for is moving that fast; a
/// reading that says they are has jumped, and counting the jump would add
/// kilometres to a walk to the shop.
const double kMaxPlausibleSpeedMetresPerSecond = 55;

class Journey {
  const Journey({
    required this.sessionId,
    required this.path,
    required this.metresTravelled,
    required this.discarded,
  });

  final String sessionId;

  /// Ordered, cleaned readings. What a replay draws.
  final List<LocationFix> path;

  final double metresTravelled;

  /// How many readings were thrown away. Surfaced rather than hidden: a journey
  /// built from 4 of 90 readings deserves to be looked at sceptically.
  final int discarded;

  bool get isEmpty => path.isEmpty;

  Duration get duration => path.length < 2
      ? Duration.zero
      : path.last.at.difference(path.first.at);

  DateTime? get startedAt => path.isEmpty ? null : path.first.at;
  DateTime? get endedAt => path.isEmpty ? null : path.last.at;
}

/// Builds a journey from one session's readings.
Journey journeyFrom(
  String sessionId,
  List<LocationFix> fixes, {
  double maxAccuracyMetres = kMaxUsefulAccuracyMetres,
  double maxSpeed = kMaxPlausibleSpeedMetresPerSecond,
}) {
  final ordered = [...fixes]..sort((a, b) => a.at.compareTo(b.at));

  var discarded = 0;
  final usable = <LocationFix>[];
  for (final fix in ordered) {
    if (fix.accuracyMetres > maxAccuracyMetres) {
      discarded++;
      continue;
    }
    usable.add(fix);
  }

  // Walk the remainder, dropping any reading that could only be reached by
  // travelling implausibly fast from the last one kept.
  final path = <LocationFix>[];
  var metres = 0.0;
  for (final fix in usable) {
    if (path.isEmpty) {
      path.add(fix);
      continue;
    }
    final previous = path.last;
    final gap = fix.at.difference(previous.at).inMilliseconds / 1000.0;
    final step = metresBetweenFixes(previous, fix);

    // Two readings at the same instant cannot imply a speed; keep the second
    // only if it has not also moved.
    if (gap <= 0) {
      if (step > maxAccuracyMetres) {
        discarded++;
        continue;
      }
      path.add(fix);
      continue;
    }

    if (step / gap > maxSpeed) {
      discarded++;
      continue;
    }

    metres += step;
    path.add(fix);
  }

  return Journey(
    sessionId: sessionId,
    path: path,
    metresTravelled: metres,
    discarded: discarded,
  );
}

/// The distance, said the way a person would say it.
///
/// Rounded hard on purpose. "About 250 metres" is useful; "247.3 metres" is a
/// precision the reading underneath it does not have.
String describeDistance(double metres) {
  if (metres < 20) return 'barely moved';
  if (metres < 1000) return '${(metres / 10).round() * 10} metres';

  final km = (metres / 100).round() / 10;
  // Nobody says "four point zero kilometres".
  final text = km == km.roundToDouble()
      ? km.round().toString()
      : km.toStringAsFixed(1);
  return '$text kilometres';
}
