/// Working out where someone actually *stopped*.
///
/// A GPS trace is mostly travel. The requirements document asks the app to
/// learn "environments the user frequently visits" (§2.B.2) — home, school,
/// workplace. Those are not the points a trace passes through most often; they
/// are the points it *stays* at. Detecting stays first is what separates a
/// place from a busy junction.
library;

import '../location/location_fix.dart';
import 'geo.dart';

/// A period spent within a small radius.
class Stay {
  const Stay({
    required this.latitude,
    required this.longitude,
    required this.arrived,
    required this.departed,
    required this.fixCount,
  });

  final double latitude;
  final double longitude;
  final DateTime arrived;
  final DateTime departed;

  /// How many readings supported it. A stay built from two fixes is a weaker
  /// claim than one built from forty.
  final int fixCount;

  Duration get duration => departed.difference(arrived);
}

/// How far apart two readings can be and still count as the same spot.
///
/// Generous, because GPS indoors drifts. A hundred metres is roughly a large
/// building and its car park, which is the granularity "home" and "the clinic"
/// need — not the granularity of which room someone is in.
const double kStayRadiusMetres = 100;

/// How long someone has to linger before it counts as being somewhere.
///
/// Below this, they are waiting at a crossing or queuing at a counter. Ten
/// minutes filters those out without losing a short errand.
const Duration kMinStayDuration = Duration(minutes: 10);

/// Extracts stays from a time-ordered trace.
///
/// The standard stay-point algorithm: walk forward while the trace stays inside
/// [radius] of the run's first fix, and emit a stay if that run also lasted at
/// least [minDuration].
List<Stay> detectStays(
  List<LocationFix> trace, {
  double radius = kStayRadiusMetres,
  Duration minDuration = kMinStayDuration,
}) {
  if (trace.length < 2) return const [];

  final ordered = [...trace]..sort((a, b) => a.at.compareTo(b.at));
  final stays = <Stay>[];

  var i = 0;
  while (i < ordered.length) {
    var j = i + 1;
    while (j < ordered.length &&
        metresBetweenFixes(ordered[i], ordered[j]) <= radius) {
      j++;
    }

    final run = ordered.sublist(i, j);
    final elapsed = run.last.at.difference(run.first.at);

    if (run.length >= 2 && elapsed >= minDuration) {
      final centre = centroidOf(run);
      stays.add(Stay(
        latitude: centre.latitude,
        longitude: centre.longitude,
        arrived: run.first.at,
        departed: run.last.at,
        fixCount: run.length,
      ));
      // Skip the whole run. Restarting inside it would emit the same stay
      // again, one fix shorter, over and over.
      i = j;
    } else {
      i++;
    }
  }

  return stays;
}
