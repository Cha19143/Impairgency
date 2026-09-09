import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/location/location_policy.dart';
import '../core/location/location_source.dart';
import '../core/sos/sos_receipt.dart';
import '../core/speech/speaker.dart';
import 'geolocator_location_source.dart';

/// Runs the legs of an emergency, and reports honestly on each.
///
/// Ordered by what each needs, so the ones that work with no account, no
/// network and no guardian go first. A phone with none of those can still make
/// a noise, and that is worth more than a queued push.
class SosEngine {
  SosEngine({
    required this.speaker,
    LocationSource? location,
    FirebaseFirestore? firestore,
    Future<bool> Function(Uri)? dial,
    Future<void> Function(Map<String, Object?> event)? writeEvent,
    this.locationBudget = const Duration(seconds: 6),
    this.guardianBudget = const Duration(seconds: 8),
  })  : _location = location ?? const GeolocatorLocationSource(),
        _firestore = firestore,
        _dial = dial ?? _defaultDial,
        _writeEvent = writeEvent;

  final Speaker speaker;
  final LocationSource _location;
  final Future<bool> Function(Uri) _dial;

  // Resolved lazily so an engine built with an injected writer never touches
  // Firebase - which is what lets the legs be tested without a project.
  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  final Future<void> Function(Map<String, Object?> event)? _writeEvent;

  Future<void> _write(Map<String, Object?> event) => _writeEvent != null
      ? _writeEvent(event)
      : _db.collection('sos_events').add({
          ...event,
          'at': FieldValue.serverTimestamp(),
        });

  /// Digits and a leading plus, nothing else.
  ///
  /// A number typed with spaces would otherwise reach the dialler as
  /// `tel:+63%20917…`, which some diallers refuse and none need. Contacts
  /// picked from the address book arrive with spaces, dashes and brackets.
  static String dialable(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'[^0-9+]'), '');

  static Future<bool> _defaultDial(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// How long the location leg may take before the rest goes without it.
  ///
  /// The alarm and the call must not queue behind a satellite.
  final Duration locationBudget;

  /// How long the guardian leg waits for the server to confirm the alert.
  ///
  /// A Firestore write completes when the *server* acknowledges it. With no
  /// signal that is never, and the SOS flow sat on "Calling for help…" for
  /// as long as the phone was offline, which is one of the ways the tester
  /// saw an emergency contact feature that did nothing. After this long the
  /// write is still queued on the device and will go when the network
  /// returns; the receipt says exactly that.
  final Duration guardianBudget;

  Future<SosReceipt> fire({
    required String? userId,
    String? contactName,
    String? contactNumber,
    required int guardianCount,
  }) async {
    final legs = <LegResult>[];

    // 1. Alarm. Needs nothing, so it is never gated on anything.
    try {
      await speaker.speak(
          'Emergency. Calling for help. Emergency. Calling for help.');
      legs.add(const LegResult(SosLeg.alarm, LegOutcome.done));
    } catch (_) {
      legs.add(const LegResult(SosLeg.alarm, LegOutcome.failed));
    }

    // 2. Location. Started before the call so the fix has time to arrive, but
    //    bounded so it cannot hold anything up.
    final availability = await _location.availability();
    final fix = await bestEffortFix(_location, timeout: locationBudget);
    final outcome = resolveLocationForSos(
      availability: availability,
      fix: fix,
      now: DateTime.now(),
    );

    // 3. Call. Works with no data connection, which is why it outranks push.
    final number = dialable(contactNumber);
    if (number.isEmpty) {
      legs.add(LegResult(SosLeg.call, LegOutcome.notConfigured,
          detail: contactName));
    } else {
      try {
        final ok = await _dial(Uri(scheme: 'tel', path: number));
        legs.add(LegResult(SosLeg.call,
            ok ? LegOutcome.done : LegOutcome.failed,
            detail: contactName));
      } catch (_) {
        legs.add(LegResult(SosLeg.call, LegOutcome.failed, detail: contactName));
      }
    }

    legs.add(LegResult(
      SosLeg.location,
      outcome.hasSomethingToSend ? LegOutcome.done : LegOutcome.failed,
      detail: outcome.spoken,
    ));

    // 4. Guardians. The document is what a guardian's listener picks up.
    //
    // Written whenever there is an account to write it against, guardians or
    // not: the event is also the record an administrator reviews, and a
    // guardian paired *after* the emergency should still be able to see it.
    // Only the receipt's wording depends on whether anyone was there to be
    // told.
    final event = <String, Object?>{
      'userId': userId,
      'cancelled': false,
      'locationSummary': outcome.spoken,
      if (contactName != null || contactNumber != null)
        'contact': {'name': contactName, 'number': contactNumber},
      if (outcome.fix != null) ...{
        'lat': outcome.fix!.latitude,
        'lng': outcome.fix!.longitude,
        'accuracy': outcome.fix!.accuracyMetres,
      },
    };
    if (userId == null || userId.isEmpty) {
      // No account means no document a guardian could read. Never written
      // under a placeholder id: the rules would refuse it, silently.
      legs.add(const LegResult(SosLeg.guardians, LegOutcome.failed,
          detail: 'You are not signed in on this phone.'));
    } else if (guardianCount == 0) {
      unawaited(_write(event).catchError((_) {}));
      legs.add(const LegResult(SosLeg.guardians, LegOutcome.notConfigured));
    } else {
      legs.add(await _alertGuardians(event));
    }

    // Sorted back into the order the receipt reads best in.
    legs.sort((a, b) =>
        SosLeg.values.indexOf(a.leg).compareTo(SosLeg.values.indexOf(b.leg)));
    return SosReceipt(legs);
  }

  Future<LegResult> _alertGuardians(Map<String, Object?> event) async {
    try {
      await _write(event).timeout(guardianBudget);
      return const LegResult(SosLeg.guardians, LegOutcome.done);
    } on TimeoutException {
      // Queued on the device. Not a success, and said so; not a failure
      // either, because giving up now would be wrong too.
      return const LegResult(SosLeg.guardians, LegOutcome.pending);
    } catch (_) {
      // Refused, or the SDK threw. Either way the user is told.
      return const LegResult(SosLeg.guardians, LegOutcome.failed);
    }
  }

  /// Records that an armed SOS was stopped before anything happened.
  ///
  /// Kept because the review timeline treats a cancelled SOS as a signal: it
  /// either means the countdown saved someone from a false alarm, or the button
  /// is too easy to hit.
  Future<void> recordCancellation(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    try {
      await _write({'userId': userId, 'cancelled': true})
          .timeout(guardianBudget);
    } catch (_) {
      // A cancellation that could not be logged is not worth telling the user
      // about; nothing was sent either way.
    }
  }
}
