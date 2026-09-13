/// Which readings are worth sending to a guardian, and when.
///
/// The user app reads a position every half minute while it is open and
/// location sharing is on. Sending every reading would be a write per user
/// per half minute for nothing: someone sitting in a lecture does not move,
/// and the guardian's card would just say the same place with a newer clock.
/// So a reading goes out when it is the first, when the user has moved, or
/// when the last one is old enough that "N minutes ago" is starting to
/// mislead - the heartbeat, which is what tells a guardian the phone is
/// still alive and still sharing.
library;

import 'dart:math' as math;

import '../places/journey.dart' show kMaxUsefulAccuracyMetres;
import 'location_fix.dart';

class SharePolicy {
  const SharePolicy({
    this.minMoveMetres = 15,
    this.heartbeat = const Duration(minutes: 5),
    this.maxAccuracyMetres = kMaxUsefulAccuracyMetres,
  });

  /// A move smaller than this is GPS wander, not the user going somewhere.
  final double minMoveMetres;

  /// How stale the guardian's copy may get before it is refreshed anyway.
  final Duration heartbeat;

  /// Wider than this and the reading is a cell-tower guess. Not sent: a
  /// guardian shown a 2 km circle would act on it as if it were a position.
  final double maxAccuracyMetres;

  bool shouldPublish({
    required LocationFix? last,
    required LocationFix next,
    required DateTime now,
  }) {
    if (next.accuracyMetres > maxAccuracyMetres) return false;
    if (last == null) return true;
    if (now.difference(last.at) >= heartbeat) return true;
    return metresBetween(last, next) >= minMoveMetres;
  }
}

/// Great-circle distance. Haversine, on a sphere: within a fraction of a
/// percent at the distances this app cares about.
double metresBetween(LocationFix a, LocationFix b) {
  const earthRadius = 6371000.0;
  final dLat = _radians(b.latitude - a.latitude);
  final dLng = _radians(b.longitude - a.longitude);
  final lat1 = _radians(a.latitude);
  final lat2 = _radians(b.latitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.sqrt(h));
}

double _radians(double degrees) => degrees * math.pi / 180;
