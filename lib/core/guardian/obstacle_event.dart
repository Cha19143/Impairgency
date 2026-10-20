/// One near or dangerous obstacle, kept for the guardian.
///
/// Written when the app speaks an urgent warning. The activity card is a
/// separate, shorter feed and is not this list.
library;

import '../location/location_fix.dart';

/// How long the same object type waits before another row.
///
/// Continuous frames of one car would otherwise fill the month. A different
/// type is not a duplicate, so it is kept at once.
const Duration kObstacleCooldown = Duration(seconds: 8);

/// Rows older than this are deleted on the user's phone, and the guardian
/// query never asks for them.
const Duration kObstacleRetention = Duration(days: 30);

/// How many rows one page of the guardian's list asks for.
const int kObstacleHistoryPageSize = 20;

/// How far back the list looks. The widest is also [kObstacleRetention].
enum ObstacleDateFilter { today, last7Days, last30Days }

extension ObstacleDateFilterLabel on ObstacleDateFilter {
  String get label => switch (this) {
        ObstacleDateFilter.today => 'Today',
        ObstacleDateFilter.last7Days => 'Last 7 days',
        ObstacleDateFilter.last30Days => 'Last 30 days',
      };
}

/// The first instant included by [filter]. Today starts at local midnight.
DateTime obstacleRangeStart(ObstacleDateFilter filter, DateTime now) {
  switch (filter) {
    case ObstacleDateFilter.today:
      final local = now.toLocal();
      return DateTime(local.year, local.month, local.day);
    case ObstacleDateFilter.last7Days:
      return now.subtract(const Duration(days: 7));
    case ObstacleDateFilter.last30Days:
      return now.subtract(kObstacleRetention);
  }
}

/// What the camera decided was worth an urgent warning, before a position
/// is attached.
class ObstacleNotice {
  const ObstacleNotice({
    required this.type,
    this.distanceMetres,
    required this.distanceApproximate,
  });

  /// The object's name: "car", "stairs", "person", or "obstacle" when the
  /// depth model saw something it could not name.
  final String type;

  /// Metres, when a box or a depth cue could estimate them.
  final double? distanceMetres;

  /// True when [distanceMetres] was estimated, or when there was no cue.
  final bool distanceApproximate;
}

/// One stored row.
class ObstacleSighting {
  const ObstacleSighting({
    required this.id,
    required this.type,
    required this.at,
    this.latitude,
    this.longitude,
    this.distanceMetres,
    required this.distanceApproximate,
  });

  final String id;
  final String type;
  final DateTime at;
  final double? latitude;
  final double? longitude;
  final double? distanceMetres;
  final bool distanceApproximate;

  bool get hasPosition => latitude != null && longitude != null;

  ObstacleSighting atPosition(LocationFix? fix) => ObstacleSighting(
        id: id,
        type: type,
        at: at,
        latitude: fix?.latitude ?? latitude,
        longitude: fix?.longitude ?? longitude,
        distanceMetres: distanceMetres,
        distanceApproximate: distanceApproximate,
      );

  Map<String, Object?> toJson() => {
        'type': type,
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
        if (distanceMetres != null) 'distanceMetres': distanceMetres,
        'distanceApproximate': distanceApproximate,
      };

  static ObstacleSighting? tryParse(String id, Map<String, Object?> data) {
    final type = data['type'];
    final at = data['at'];
    if (type is! String || type.trim().isEmpty || at is! DateTime) return null;
    final lat = data['lat'];
    final lng = data['lng'];
    final distance = data['distanceMetres'];
    return ObstacleSighting(
      id: id,
      type: type.trim(),
      at: at,
      latitude: lat is num ? lat.toDouble() : null,
      longitude: lng is num ? lng.toDouble() : null,
      distanceMetres: distance is num ? distance.toDouble() : null,
      distanceApproximate: data['distanceApproximate'] != false,
    );
  }
}

/// One row per object type inside [kObstacleCooldown].
class ObstacleThrottle {
  ObstacleThrottle({this.window = kObstacleCooldown});

  final Duration window;
  final _last = <String, DateTime>{};

  /// Whether [type] may be stored at [now], and remembers it if so.
  bool admit(String type, DateTime now) {
    final key = type.trim().toLowerCase();
    if (key.isEmpty) return false;
    final last = _last[key];
    if (last != null && now.difference(last) < window) return false;
    _last[key] = now;
    return true;
  }
}

/// The one decision that a near obstacle is worth acting on.
///
/// Null when this type was already kept inside the cooldown, or the name is
/// blank. A later guardian notice or a short video clip should call this,
/// not look at the camera again, so the cooldown stays one rule.
ObstacleSighting? keepImportantObstacle({
  required ObstacleThrottle throttle,
  required ObstacleNotice notice,
  required DateTime at,
  LocationFix? fix,
}) {
  final type = notice.type.trim();
  if (!throttle.admit(type, at)) return null;
  return ObstacleSighting(
    id: '',
    type: type,
    at: at,
    latitude: fix?.latitude,
    longitude: fix?.longitude,
    distanceMetres: notice.distanceMetres,
    distanceApproximate: notice.distanceApproximate,
  );
}

/// "Car", "Fire hydrant". The stored type stays the detector's own word.
String obstacleTypeLabel(String type) {
  final trimmed = type.trim();
  if (trimmed.isEmpty) return 'Obstacle';
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

/// "14.84321, 120.81150", or that the phone had no position.
String obstacleLocationText(ObstacleSighting sighting) {
  final lat = sighting.latitude;
  final lng = sighting.longitude;
  if (lat == null || lng == null) return 'Location unavailable';
  return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

/// "About 2 metres" when the distance was estimated from the camera.
String obstacleDistanceText(ObstacleSighting sighting) {
  final metres = sighting.distanceMetres;
  if (metres == null) return 'Distance unknown';
  final rounded = metres.round();
  final unit = rounded == 1 ? 'metre' : 'metres';
  final words = '$rounded $unit';
  return sighting.distanceApproximate ? 'About $words' : words;
}

/// What the empty list should say, or null when there are rows to show.
String? obstacleHistoryEmptyMessage({
  required bool loading,
  required bool hasError,
  required int fetched,
  required int visible,
  required ObstacleDateFilter date,
  required bool typeNarrowed,
}) {
  if (loading || hasError || visible > 0) return null;
  if (fetched == 0 &&
      date == ObstacleDateFilter.last30Days &&
      !typeNarrowed) {
    return 'No obstacle history yet.';
  }
  return 'No results for this filter.';
}
