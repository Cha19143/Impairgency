/// What to send, and what to say, when the app needs a position.
///
/// Pure, so the rules that matter in an emergency can be tested without a
/// device, a permission prompt, or a sky view of a GPS satellite.
library;

import 'location_fix.dart';
import 'location_source.dart';

/// How much a fix can be trusted as *where the user is now*.
enum LocationTrust {
  /// Recent enough to call it their location without qualification.
  fresh,

  /// Real, but old. It may still be the most useful thing anyone has - so it
  /// is sent, and it is always described with its age. It is never called
  /// "current".
  lastKnown,

  /// Nothing to send.
  none,
}

/// A fix older than this is no longer described as where the user is.
const Duration kFreshEnough = Duration(minutes: 2);

/// Above this, the reading is a wide guess rather than a position, and saying
/// it plainly is more use than a number.
const double kVagueAccuracyMetres = 500;

class LocationOutcome {
  const LocationOutcome({
    required this.trust,
    required this.fix,
    required this.spoken,
  });

  final LocationTrust trust;

  /// The reading to attach, if any. Present for both [LocationTrust.fresh] and
  /// [LocationTrust.lastKnown]: an old position still narrows a search, and
  /// withholding it helps nobody as long as its age travels with it.
  final LocationFix? fix;

  /// What the receipt says, out loud. Written to be true when read alone.
  final String spoken;

  bool get hasSomethingToSend => fix != null;
}

/// How long ago, said the way a person would say it.
///
/// Public because [resolveLocationForSos] only ever reaches it with ages above
/// [kFreshEnough], which would leave the shorter phrasings shipped and
/// untested. They are reachable elsewhere - a guardian screen showing when a
/// user was last seen wants all of them.
String describeAge(Duration d) {
  if (d.inMinutes < 1) return 'less than a minute ago';
  if (d.inMinutes == 1) return 'a minute ago';
  if (d.inMinutes < 60) return '${d.inMinutes} minutes ago';
  final hours = d.inHours;
  if (hours == 1) return 'an hour ago';
  if (hours < 24) return '$hours hours ago';
  return 'more than a day ago';
}

/// Decides what an SOS should carry and say.
///
/// [availability] is why the app could or could not read a position;
/// [fix] is whatever it managed to obtain, fresh or remembered.
LocationOutcome resolveLocationForSos({
  required LocationAvailability availability,
  required LocationFix? fix,
  required DateTime now,
}) {
  if (fix == null) {
    // Each of these is a different problem with a different remedy, so the app
    // says which one it is rather than "location unavailable".
    final spoken = switch (availability) {
      LocationAvailability.ready =>
        'We could not get your location in time, so it was not sent.',
      LocationAvailability.denied =>
        'Your location was not sent, because location sharing is off.',
      LocationAvailability.deniedForever =>
        'Your location was not sent. Location is blocked for this app in '
            'Settings.',
      LocationAvailability.serviceDisabled =>
        'Your location was not sent, because location is turned off on this '
            'phone.',
    };
    return LocationOutcome(
        trust: LocationTrust.none, fix: null, spoken: spoken);
  }

  final age = fix.ageAt(now);
  final vague = fix.accuracyMetres > kVagueAccuracyMetres;

  if (age <= kFreshEnough) {
    return LocationOutcome(
      trust: LocationTrust.fresh,
      fix: fix,
      spoken: vague
          ? 'Your location was sent, but it is only accurate to about '
              '${(fix.accuracyMetres / 100).round() * 100} metres.'
          : 'Your location was sent.',
    );
  }

  // Old, and said so. "Your location was sent" would be a lie here, and the
  // person acting on it is looking for someone.
  return LocationOutcome(
    trust: LocationTrust.lastKnown,
    fix: fix,
    spoken: 'Your last known location, from ${describeAge(age)}, was sent. '
        'We could not get a newer one.',
  );
}

/// What to say when asking for permission has just failed.
///
/// [LocationAvailability.deniedForever] is the only one where asking again is
/// pointless, so it is the only one that sends the user to Settings.
String permissionGuidance(LocationAvailability availability) =>
    switch (availability) {
      LocationAvailability.ready => 'Location sharing is on.',
      LocationAvailability.denied =>
        'Without location, an emergency SOS can sound the alarm and call your '
            'contact, but it cannot tell them where you are.',
      LocationAvailability.deniedForever =>
        'Location is blocked for this app. To turn it back on, open Settings, '
            'find ImpairGency, and allow location while using the app.',
      LocationAvailability.serviceDisabled =>
        'Location is turned off on this phone. Turn it on in Settings for an '
            'SOS to be able to share where you are.',
    };
