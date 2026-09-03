/// Turning an SOS document into something a guardian sees.
///
/// Pure, because the decision *not* to alert matters as much as the alert. A
/// guardian who opens the app on Tuesday must not be shown Monday's emergency
/// as though it were happening now.
library;

class SosEvent {
  const SosEvent({
    required this.id,
    required this.userId,
    required this.at,
    this.locationSummary,
    this.cancelled = false,
  });

  final String id;
  final String userId;
  final DateTime at;

  /// Already-written prose from `resolveLocationForSos`, or null if the SOS
  /// carried no position at all.
  final String? locationSummary;

  /// Set when the user cancelled during the arming countdown.
  final bool cancelled;

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
      title: '${name?.trim().isNotEmpty == true ? name!.trim() : 'Someone you watch over'} needs help',
      body: event.locationSummary ?? 'No location was available.',
    );
