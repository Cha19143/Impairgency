import 'location_fix.dart';

/// Why the app can or cannot read a position right now.
///
/// Separated from a plain bool because the four failures need four different
/// things said to the user, and three of them are recoverable.
enum LocationAvailability {
  /// Permission granted and the device's location services are on.
  ready,

  /// Not asked yet, or asked and declined once. Asking again is allowed.
  denied,

  /// Declined permanently, or restricted by policy. Only Settings can fix it,
  /// so the app must stop asking and say where to go instead.
  deniedForever,

  /// Permission is fine; the device has location switched off system-wide.
  serviceDisabled,
}

abstract interface class LocationSource {
  Future<LocationAvailability> availability();

  /// Prompts if that is still allowed, and reports the result.
  Future<LocationAvailability> requestPermission();

  /// A reading, or null if one could not be obtained inside [timeout].
  ///
  /// Never throws for the ordinary failures - a permission prompt declined
  /// during an emergency should not take the SOS down with it.
  Future<LocationFix?> currentFix({Duration timeout});

  /// The most recent reading the platform already had, without waiting for a
  /// new one. Cheap, and usually the difference between an SOS that carries a
  /// position and one that does not.
  Future<LocationFix?> lastKnownFix();
}
