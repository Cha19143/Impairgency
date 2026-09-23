/// The direction someone is walking, when the phone does not say.
///
/// Guidance needs the direction of travel to tell left from right at the
/// start. Many phones report no GPS course at all - and the platform plugin
/// then sent 0.0, which read as walking due north. When a fix has no course,
/// this works one out from where the last readings were: far enough apart
/// to mean something, recent enough to be the same walk.
///
/// Pure, so it is tested with a list of positions.
library;

import '../navigation/guidance.dart' show bearingDegrees;
import '../places/geo.dart';
import 'location_fix.dart';

/// Readings closer together than this say nothing about direction: a
/// phone's position wanders a few metres standing still.
const double kCourseMinMetres = 4;

/// Readings further apart in time than this are not the same stretch of
/// walking.
const Duration kCourseMaxGap = Duration(seconds: 15);

class CourseTracker {
  LocationFix? _anchor;

  /// [fix], with a course and speed worked out from the walk so far when it
  /// came without them. A fix with its own course is left alone.
  LocationFix withCourse(LocationFix fix) {
    final anchor = _anchor;
    if (anchor == null || fix.at.difference(anchor.at) > kCourseMaxGap) {
      _anchor = fix;
      return fix;
    }
    if (fix.headingDegrees != null && fix.speedMetresPerSecond != null) {
      _anchor = fix;
      return fix;
    }
    final metres = metresBetween(
        anchor.latitude, anchor.longitude, fix.latitude, fix.longitude);
    if (metres < kCourseMinMetres) return fix;
    _anchor = fix;
    final seconds = fix.at.difference(anchor.at).inMilliseconds / 1000;
    if (seconds <= 0) return fix;
    return LocationFix(
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyMetres: fix.accuracyMetres,
      at: fix.at,
      headingDegrees: fix.headingDegrees ??
          bearingDegrees(
              anchor.latitude, anchor.longitude, fix.latitude, fix.longitude),
      speedMetresPerSecond: fix.speedMetresPerSecond ?? metres / seconds,
    );
  }
}
