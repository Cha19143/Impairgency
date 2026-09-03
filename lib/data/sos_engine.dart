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
  })  : _location = location ?? const GeolocatorLocationSource(),
        _db = firestore ?? FirebaseFirestore.instance,
        _dial = dial ?? _defaultDial;

  final Speaker speaker;
  final LocationSource _location;
  final FirebaseFirestore _db;
  final Future<bool> Function(Uri) _dial;

  static Future<bool> _defaultDial(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// How long the location leg may take before the rest goes without it.
  ///
  /// The alarm and the call must not queue behind a satellite.
  static const Duration locationBudget = Duration(seconds: 6);

  Future<SosReceipt> fire({
    required String userId,
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
    if (contactNumber == null || contactNumber.trim().isEmpty) {
      legs.add(LegResult(SosLeg.call, LegOutcome.notConfigured,
          detail: contactName));
    } else {
      try {
        final ok = await _dial(Uri(scheme: 'tel', path: contactNumber.trim()));
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
    if (guardianCount == 0) {
      legs.add(const LegResult(SosLeg.guardians, LegOutcome.notConfigured));
    } else {
      try {
        await _db.collection('sos_events').add({
          'userId': userId,
          'at': FieldValue.serverTimestamp(),
          'cancelled': false,
          'locationSummary': outcome.spoken,
          if (outcome.fix != null) ...{
            'lat': outcome.fix!.latitude,
            'lng': outcome.fix!.longitude,
            'accuracy': outcome.fix!.accuracyMetres,
          },
        });
        legs.add(const LegResult(SosLeg.guardians, LegOutcome.done));
      } catch (_) {
        // Written, or not. Either way the user is told which.
        legs.add(const LegResult(SosLeg.guardians, LegOutcome.failed));
      }
    }

    // Sorted back into the order the receipt reads best in.
    legs.sort((a, b) =>
        SosLeg.values.indexOf(a.leg).compareTo(SosLeg.values.indexOf(b.leg)));
    return SosReceipt(legs);
  }

  /// Records that an armed SOS was stopped before anything happened.
  ///
  /// Kept because the review timeline treats a cancelled SOS as a signal: it
  /// either means the countdown saved someone from a false alarm, or the button
  /// is too easy to hit.
  Future<void> recordCancellation(String userId) async {
    try {
      await _db.collection('sos_events').add({
        'userId': userId,
        'at': FieldValue.serverTimestamp(),
        'cancelled': true,
      });
    } catch (_) {
      // A cancellation that could not be logged is not worth telling the user
      // about; nothing was sent either way.
    }
  }
}
