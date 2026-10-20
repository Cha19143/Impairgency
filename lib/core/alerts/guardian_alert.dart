/// One reusable notice for a paired guardian.
///
/// A route deviation and a one-hour stay both go through here. A later fall
/// alert should call the same sender, not invent a second collection.
library;

import '../location/location_fix.dart';

/// Left the planned route. One per deviation, with a cooldown.
const String kGuardianAlertRouteDeviation = 'route_deviation';

/// Stayed inside a small radius for an hour, and not at Home.
const String kGuardianAlertStationary = 'stationary_1h';

/// Wandering on and off the route must not notify on every new episode.
const Duration kRouteDeviationAlertCooldown = Duration(minutes: 5);

/// Lets the first route-deviation alert through, then waits [gap].
class GuardianAlertCooldown {
  GuardianAlertCooldown({this.gap = kRouteDeviationAlertCooldown});

  final Duration gap;
  DateTime? _last;

  bool admit(DateTime now) {
    final last = _last;
    if (last != null && now.difference(last) < gap) return false;
    _last = now;
    return true;
  }
}

class GuardianAlert {
  const GuardianAlert({
    required this.id,
    required this.userId,
    required this.kind,
    required this.message,
    required this.at,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String userId;
  final String kind;
  final String message;
  final DateTime at;
  final double? latitude;
  final double? longitude;

  static GuardianAlert? tryParse(
    String userId,
    String id,
    Map<String, dynamic> data,
    DateTime? at,
  ) {
    final kind = data['kind'];
    final message = data['message'];
    if (kind is! String || message is! String || at == null) return null;
    final lat = data['lat'];
    final lng = data['lng'];
    return GuardianAlert(
      id: id,
      userId: userId,
      kind: kind,
      message: message,
      at: at,
      latitude: lat is num ? lat.toDouble() : null,
      longitude: lng is num ? lng.toDouble() : null,
    );
  }
}

/// Fields written with the alert. The repository adds the Firestore clock.
Map<String, Object?> guardianAlertFields({
  required String kind,
  required String message,
  LocationFix? position,
}) => {
  'kind': kind,
  'message': message,
  if (position != null) 'lat': position.latitude,
  if (position != null) 'lng': position.longitude,
};

/// Fresh enough to show, and not already shown.
bool shouldShowGuardianAlert({
  required GuardianAlert alert,
  required DateTime now,
  required Set<String> alreadyShown,
  Duration maxAge = const Duration(minutes: 15),
}) {
  if (alreadyShown.contains(alert.id)) return false;
  final age = now.difference(alert.at);
  if (age.isNegative) return true;
  return age <= maxAge;
}

/// The sentence on the guardian's notification.
///
/// The two kinds this step sends have fixed wording. Any later kind uses
/// the message the user phone stored.
String guardianAlertSentence(GuardianAlert alert, String? name) {
  final who = name?.trim().isNotEmpty == true
      ? name!.trim()
      : 'Someone you watch over';
  switch (alert.kind) {
    case kGuardianAlertRouteDeviation:
      return '$who left the planned route';
    case kGuardianAlertStationary:
      return '$who has been in one place for 1 hour';
    default:
      final message = alert.message.trim();
      return message.isEmpty ? who : '$who. $message';
  }
}

/// Payload prefix for a tap that opens live location. Anything else,
/// including an SOS event id, is left alone.
const String kGuardianAlertLivePrefix = 'live:';

String guardianAlertLivePayload(String userId) =>
    '$kGuardianAlertLivePrefix$userId';
