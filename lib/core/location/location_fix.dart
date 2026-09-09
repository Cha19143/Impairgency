/// A single position reading.
library;

/// Below this speed a GPS heading is noise. Shared with `guidance.dart`.
const double kMinSpeedForHeading = 0.5;

class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.at,
    this.headingDegrees,
    this.speedMetresPerSecond,
  });

  final double latitude;
  final double longitude;

  /// Radius of uncertainty. A 2000 m accuracy is a cell-tower guess, not a
  /// position, and the app should not read it out as though it were one.
  final double accuracyMetres;

  final DateTime at;

  /// Direction of *travel*, clockwise from north, if the platform gave one.
  /// Not the direction the phone faces: GPS has no compass, so this is only
  /// meaningful while moving. See [usableHeading].
  final double? headingDegrees;

  final double? speedMetresPerSecond;

  /// The heading, when the user is moving fast enough for it to mean
  /// anything. Standing still, GPS course is noise, and guidance built on
  /// noise tells someone to turn around on the spot.
  double? get usableHeading {
    final h = headingDegrees;
    final v = speedMetresPerSecond;
    if (h == null || h.isNaN || h < 0) return null;
    if (v == null || v.isNaN || v < kMinSpeedForHeading) return null;
    return h % 360;
  }

  Duration ageAt(DateTime now) => now.difference(at);

  Map<String, Object?> toJson() => {
        'lat': latitude,
        'lng': longitude,
        'accuracy': accuracyMetres,
        'at': at.toUtc().toIso8601String(),
      };

  @override
  String toString() =>
      'LocationFix(${latitude.toStringAsFixed(5)}, '
      '${longitude.toStringAsFixed(5)}, ±${accuracyMetres.round()}m)';
}
