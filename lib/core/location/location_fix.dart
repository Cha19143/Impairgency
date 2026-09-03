/// A single position reading.
library;

class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.at,
  });

  final double latitude;
  final double longitude;

  /// Radius of uncertainty. A 2000 m accuracy is a cell-tower guess, not a
  /// position, and the app should not read it out as though it were one.
  final double accuracyMetres;

  final DateTime at;

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
