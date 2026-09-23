/// Turning an SOS document into something a guardian sees.
///
/// Pure, because the decision *not* to alert matters as much as the alert. A
/// guardian who opens the app on Tuesday must not be shown Monday's emergency
/// as though it were happening now.
library;

import '../location/location_policy.dart';

class SosEvent {
  const SosEvent({
    required this.id,
    required this.userId,
    required this.at,
    this.locationSummary,
    this.cancelled = false,
    this.resolvedAt,
    this.resolvedBy,
  });

  final String id;
  final String userId;
  final DateTime at;

  /// Already-written prose from `resolveLocationForSos`, or null if the SOS
  /// carried no position at all.
  final String? locationSummary;

  /// Set when the user cancelled during the arming countdown.
  final bool cancelled;

  /// When the emergency was said to be over: by the user saying "I am
  /// okay" after the call, or by an administrator. Null while it is not.
  final DateTime? resolvedAt;

  /// 'user', or the uid of the administrator who marked it resolved.
  final String? resolvedBy;

  bool get resolved => resolvedAt != null;

  bool get resolvedByUser => resolvedBy == 'user';

  Duration ageAt(DateTime now) => now.difference(at);
}

class SosAlert {
  const SosAlert({
    required this.eventId,
    required this.title,
    required this.body,
  });

  final String eventId;
  final String title;
  final String body;
}

/// How stale an event can be and still be worth waking someone for.
///
/// A Firestore listener replays everything matching its query when it attaches,
/// so without this every app launch would fire every past emergency at once.
/// Fifteen minutes is long enough to survive a phone reboot mid-incident and
/// short enough that nothing historical gets through.
const Duration kAlertableAge = Duration(minutes: 15);

/// Whether this event should interrupt the guardian right now.
bool shouldAlert({
  required SosEvent event,
  required DateTime now,
  required Set<String> alreadyAlerted,
  Duration maxAge = kAlertableAge,
}) {
  if (event.cancelled) return false;
  // Over before this guardian heard of it: [shouldAlertOkay] says so instead.
  if (event.resolved) return false;
  if (alreadyAlerted.contains(event.id)) return false;
  if (event.ageAt(now) > maxAge) return false;
  // A clock skewed into the future would otherwise make every event look
  // ancient or permanently fresh depending on sign.
  if (event.ageAt(now).isNegative) return true;
  return true;
}

/// The words a guardian sees on their lock screen.
///
/// Names the person, because a guardian may watch more than one, and a
/// notification that says only "Emergency" tells them to unlock the phone
/// before they know who to call.
SosAlert buildSosAlert(SosEvent event, {String? name}) => SosAlert(
      eventId: event.id,
      title: '${_who(name)} needs help',
      body: event.locationSummary ?? 'No location was available.',
    );

String _who(String? name) =>
    name?.trim().isNotEmpty == true ? name!.trim() : 'Someone you watch over';

/// Whether to tell the guardian the emergency is over.
///
/// Once per event, and only while fresh, by the same rule as the alert: a
/// guardian opening the app tomorrow does not need yesterday's all-clear.
bool shouldAlertOkay({
  required SosEvent event,
  required DateTime now,
  required Set<String> alreadyTold,
  Duration maxAge = kAlertableAge,
}) {
  final at = event.resolvedAt;
  if (at == null || event.cancelled) return false;
  if (alreadyTold.contains(event.id)) return false;
  return now.difference(at) <= maxAge;
}

/// The all-clear. Shown under the emergency's own id, so on the guardian's
/// lock screen it replaces "needs help" rather than sitting under it.
SosAlert buildOkAlert(SosEvent event,
    {String? name, required DateTime now}) {
  final who = _who(name);
  final when = describeAge(now.difference(event.at));
  return SosAlert(
    eventId: event.id,
    title: event.resolvedByUser
        ? '$who says they are okay'
        : "$who's emergency was marked resolved",
    body: event.resolvedByUser
        ? 'They called for help $when. Call them if you are not sure.'
        : 'They called for help $when. An administrator marked it resolved. '
            'Call them if you are not sure.',
  );
}
