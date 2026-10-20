/// How far a near obstacle is, from the cues the detector already has.
///
/// Nothing in the camera pipeline measures metres. A box's [extent] is the
/// larger side as a fraction of the frame, and bigger means nearer. Depth
/// nearness, when that model is on, is 0 to 1 inside one frame. Both
/// estimates are approximate.
library;

import '../guardian/obstacle_event.dart';
import 'depth.dart';
import 'detection.dart';

/// Chosen so a box at the "Stop" size — [Detection.proximity] calls anything
/// over 0.55 of the frame very close — is about 1.5 metres.
///
/// `0.55 * 1.5` is 0.825; 0.85 keeps that and makes the arithmetic obvious.
/// A box at the "close" size (0.25 of the frame) is then about 3.4 metres.
const double kObstacleApparentMetres = 0.85;

/// The nearest and farthest an estimate is allowed to claim.
const double kObstacleDistanceFloorMetres = 0.5;
const double kObstacleDistanceCeilingMetres = 15;

/// Depth nearness of 0.8 is the unnamed "Stop". `1.2 / 0.8` is 1.5 metres,
/// the same "right in front of you" the box estimate uses.
const double kObstacleNearnessMetres = 1.2;

/// Metres from a box's [extent]. Always an estimate.
double estimateDistanceFromExtent(double extent) {
  if (extent <= 0) return kObstacleDistanceCeilingMetres;
  final metres = kObstacleApparentMetres / extent;
  if (metres < kObstacleDistanceFloorMetres) return kObstacleDistanceFloorMetres;
  if (metres > kObstacleDistanceCeilingMetres) {
    return kObstacleDistanceCeilingMetres;
  }
  return metres;
}

/// Metres from a depth model's nearness, 0 to 1 in that frame. Always an
/// estimate. Nearness of 0 has no cue, so this returns the far cap.
double estimateDistanceFromNearness(double nearness) {
  if (nearness <= 0) return kObstacleDistanceCeilingMetres;
  final metres = kObstacleNearnessMetres / nearness;
  if (metres < kObstacleDistanceFloorMetres) return kObstacleDistanceFloorMetres;
  if (metres > kObstacleDistanceCeilingMetres) {
    return kObstacleDistanceCeilingMetres;
  }
  return metres;
}

/// The obstacle behind an urgent warning, with a distance taken from the
/// box or, for an unnamed blockage, from depth nearness.
///
/// Null when this frame is not an urgent warning. Spoken stairs that are
/// not a "Stop" stay on the activity card and are not a history row.
ObstacleNotice? urgentObstacleNotice({
  required Guidance guidance,
  required List<Detection> detections,
  required DepthReading depth,
}) {
  if (!guidance.urgent) return null;
  final type = guidance.label?.trim() ?? '';
  if (type.isEmpty) return null;

  Detection? largest;
  for (final detection in detections) {
    if (detection.label != type) continue;
    if (largest == null || detection.extent > largest.extent) {
      largest = detection;
    }
  }
  if (largest != null && largest.extent > 0) {
    return ObstacleNotice(
      type: type,
      distanceMetres: estimateDistanceFromExtent(largest.extent),
      distanceApproximate: true,
    );
  }
  if (depth.isBlocked && depth.nearness > 0) {
    return ObstacleNotice(
      type: type,
      distanceMetres: estimateDistanceFromNearness(depth.nearness),
      distanceApproximate: true,
    );
  }
  return ObstacleNotice(
    type: type,
    distanceApproximate: true,
  );
}
