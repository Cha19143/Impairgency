/// What a guardian sees about each person they watch over, and what the
/// Call button does.
///
/// Pure, so the sentences a guardian relies on - "last seen twelve minutes
/// ago", "not sharing their location" - are asserted without Firestore.
library;

import '../location/location_fix.dart';
import '../location/location_policy.dart';
import 'activity.dart';

/// What the guardian dashboard knows about one visually impaired user.
class WatchedUser {
  const WatchedUser({
    required this.uid,
    this.name,
    this.phone,
    this.contactName,
    this.contactNumber,
    this.sharesLocation = false,
    this.fix,
    this.lastSos,
    this.sharesActivity = false,
    this.activity = const [],
  });

  final String uid;
  final String? name;

  /// Their own number, from the personal-information step. May be absent.
  final String? phone;

  /// Their emergency contact, the same person SOS rings.
  final String? contactName;
  final String? contactNumber;

  /// `consent.location`. Off means the server refuses the fixes below and
  /// the dashboard must say so rather than show nothing.
  final bool sharesLocation;

  /// The most recent position the server let us read, if any.
  final LocationFix? fix;

  /// When they last fired an SOS that was not cancelled, if ever.
  final DateTime? lastSos;

  /// `consent.activity`. Off means the rows below are refused and the card
  /// says so.
  final bool sharesActivity;

  /// The last few things the app noticed, newest first.
  final List<ActivityEvent> activity;

  String get displayName =>
      name?.trim().isNotEmpty == true ? name!.trim() : 'Someone you watch over';
}

/// Who the Call button rings, and how the button says so.
///
/// The tester asked for "the same target and behavior as the user-side
/// emergency SOS". The user-side SOS rings the emergency contact - which,
/// for the guardian, is usually themselves. So the button rings the *user*
/// when the user gave a number, and falls back to their emergency contact
/// when they did not; either way the label names who is about to be rung,
/// because a guardian who taps Call and reaches themselves has been misled.
class CallTarget {
  const CallTarget({required this.number, required this.label});

  final String number;

  /// "Call Ana" or "Call Ana's emergency contact, Mum".
  final String label;
}

CallTarget? callTargetFor(WatchedUser user) {
  final own = _dialable(user.phone);
  if (own.isNotEmpty) {
    return CallTarget(number: own, label: 'Call ${user.displayName}');
  }
  final contact = _dialable(user.contactNumber);
  if (contact.isNotEmpty) {
    final who = user.contactName?.trim().isNotEmpty == true
        ? user.contactName!.trim()
        : 'their emergency contact';
    return CallTarget(
      number: contact,
      label: "Call ${user.displayName}'s emergency contact, $who",
    );
  }
  return null;
}

/// What the dashboard says when there is nobody to call.
String noCallTargetMessage(WatchedUser user) =>
    '${user.displayName} has not given a phone number or an emergency '
    'contact, so there is nobody to call from here.';

String _dialable(String? raw) =>
    (raw ?? '').replaceAll(RegExp(r'[^0-9+]'), '');

/// The location line, written to be true when read alone.
///
/// Four cases, four sentences, none of them "location unavailable". A stale
/// fix is shown - an old position still narrows a search - and always with
/// its age, so a guardian looking at a pin from this morning knows it.
String describeWatchedLocation(WatchedUser user, {required DateTime now}) {
  final name = user.displayName;
  if (!user.sharesLocation) {
    return '$name is not sharing their location. They can turn it on in '
        'their app under "What the app is using".';
  }
  final fix = user.fix;
  if (fix == null) {
    return '$name is sharing their location, but none has been recorded yet.';
  }
  final age = fix.ageAt(now);
  final accuracy = fix.accuracyMetres > kVagueAccuracyMetres
      ? ', accurate only to about '
          '${(fix.accuracyMetres / 100).round() * 100} metres'
      : '';
  if (age <= kFreshEnough) {
    return '$name is here now$accuracy.';
  }
  return '$name was last seen ${describeAge(age)}$accuracy.';
}

/// The map link for a fix. A plain web URL, which every phone can open.
Uri mapLinkFor(LocationFix fix) => Uri.https(
      'www.google.com',
      '/maps/search/',
      {'api': '1', 'query': '${fix.latitude},${fix.longitude}'},
    );

/// The SOS line under a user, or null when there is nothing to say.
String? describeLastSos(WatchedUser user, {required DateTime now}) {
  final at = user.lastSos;
  if (at == null) return null;
  final age = now.difference(at);
  if (age > const Duration(hours: 24)) return null;
  return 'Called for help ${describeAge(age)}.';
}
