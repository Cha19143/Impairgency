import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../core/contacts/emergency_contact.dart';
import '../core/location/location_policy.dart';
import '../core/location/location_source.dart';
import '../core/sos/sos_receipt.dart';
import '../core/speech/speaker.dart';
import 'geolocator_location_source.dart';

/// What the phone says as soon as an SOS fires.
const String kSosAlarm =
    'Emergency. Calling for help. Emergency. Calling for help.';

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
    Future<void> Function(String id, Map<String, Object?> fields)? updateEvent,
    String Function()? newEventId,
    this.locationBudget = const Duration(seconds: 6),
    this.guardianBudget = const Duration(seconds: 8),
  })  : _location = location ?? const GeolocatorLocationSource(),
        _firestore = firestore,
        _dial = dial ?? _defaultDial,
        _writeEvent = writeEvent,
        _updateEvent = updateEvent,
        _newEventId = newEventId;

  final Speaker speaker;
  final LocationSource _location;
  final Future<bool> Function(Uri) _dial;

  // Resolved lazily so an engine built with an injected writer never touches
  // Firebase - which is what lets the legs be tested without a project.
  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  final Future<void> Function(Map<String, Object?> event)? _writeEvent;
  final Future<void> Function(String id, Map<String, Object?> fields)?
      _updateEvent;
  final String Function()? _newEventId;

  /// Writes an event: under [id] when given, so it can be found again to
  /// be resolved, otherwise under a new one. An injected writer sees the id
  /// as `eventId`.
  Future<void> _write(Map<String, Object?> event, {String? id}) {
    if (_writeEvent != null) {
      return _writeEvent({...event, if (id != null) 'eventId': id});
    }
    final data = {...event, 'at': FieldValue.serverTimestamp()};
    final events = _db.collection('sos_events');
    return id == null ? events.add(data) : events.doc(id).set(data);
  }

  Future<void> _update(String id, Map<String, Object?> fields) =>
      _updateEvent != null
          ? _updateEvent(id, fields)
          : _db.collection('sos_events').doc(id).update({
              ...fields,
              if (fields['status'] == 'resolved')
                'resolvedAt': FieldValue.serverTimestamp(),
            });

  String _eventId() =>
      _newEventId?.call() ??
      (_writeEvent != null
          ? 'sos-${DateTime.now().microsecondsSinceEpoch}'
          : _db.collection('sos_events').doc().id);

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

  /// Runs the legs. [contacts] is the calling order; only the first is rung
  /// here, because a phone places one call at a time. The rest are reached
  /// through [callNext] from the receipt, and all of them are written on the
  /// event so a guardian sees the whole list.
  ///
  /// [cancelled] completes when the user says cancel. The alarm and the
  /// position take seconds, and until the dialler opens there is still
  /// nothing to undo, so it is honoured up to then: nobody is called, no
  /// guardian is alerted, and the receipt says why. [onCommitted] is called
  /// once it no longer can be - just before the call.
  Future<SosReceipt> fire({
    required String? userId,
    List<EmergencyContact> contacts = const [],
    required int guardianCount,
    Future<void>? cancelled,
    void Function()? onCommitted,
  }) async {
    final first = contacts.isEmpty ? null : contacts.first;
    final contactName = first?.name;
    final contactNumber = first?.number;
    final legs = <LegResult>[];

    // Registered before anything waits on [cancelled], so the flag is set by
    // the time any of those waits ends.
    var stopped = false;
    unawaited(cancelled?.then((_) => stopped = true));
    Future<T?> unlessCancelled<T>(Future<T> work) => cancelled == null
        ? work
        : Future.any<T?>([work, cancelled.then((_) => null)]);

    // 1. Alarm. Needs nothing, so it is never gated on anything.
    try {
      await unlessCancelled(speaker.speak(kSosAlarm));
      legs.add(const LegResult(SosLeg.alarm, LegOutcome.done));
    } catch (_) {
      legs.add(const LegResult(SosLeg.alarm, LegOutcome.failed));
    }
    if (stopped) return _cancelledBeforeCall(userId, legs);

    // 2. Location. Started before the call so the fix has time to arrive, but
    //    bounded so it cannot hold anything up.
    final availability = await _location.availability();
    final fix = await unlessCancelled(
        bestEffortFix(_location, timeout: locationBudget));
    if (stopped) return _cancelledBeforeCall(userId, legs);
    onCommitted?.call();
    final outcome = resolveLocationForSos(
      availability: availability,
      fix: fix,
      now: DateTime.now(),
    );

    // 3. The record. The document is what a guardian's listener picks up.
    //
    // Written whenever there is an account to write it against, guardians or
    // not: the event is also the record an administrator reviews, and a
    // guardian paired *after* the emergency should still be able to see it.
    // Only the receipt's wording depends on whether anyone was there to be
    // told.
    //
    // Started before the call, not after it: the dialler puts the app behind
    // the call, and a phone dropped or killed during it used to lose the
    // record altogether. Once started, the write is on the device's queue
    // and goes when there is a connection. Its id is chosen here so "I am
    // okay" after the call can find it again.
    final event = <String, Object?>{
      'userId': userId,
      'cancelled': false,
      'status': 'active',
      'locationSummary': outcome.spoken,
      if (contactName != null || contactNumber != null)
        'contact': {'name': contactName, 'number': contactNumber},
      if (contacts.isNotEmpty)
        'contacts': contacts.map((c) => c.toJson()).toList(),
      if (outcome.fix != null) ...{
        'lat': outcome.fix!.latitude,
        'lng': outcome.fix!.longitude,
        'accuracy': outcome.fix!.accuracyMetres,
      },
    };
    // No account means no document a guardian could read. Never written
    // under a placeholder id: the rules would refuse it, silently.
    final signedIn = userId != null && userId.isNotEmpty;
    final eventId = signedIn ? _eventId() : null;
    final Future<void>? written;
    if (eventId != null) {
      written = _write(event, id: eventId);
      // Its outcome is read below when there are guardians to tell; with
      // none, a failure has nobody to be reported to.
      unawaited(written.catchError((_) {}));
    } else {
      written = null;
    }

    // 4. Call. Works with no data connection, which is why it outranks push.
    if (first == null) {
      legs.add(const LegResult(SosLeg.call, LegOutcome.notConfigured));
    } else {
      legs.add(await call(first));
    }

    legs.add(LegResult(
      SosLeg.location,
      outcome.hasSomethingToSend ? LegOutcome.done : LegOutcome.failed,
      detail: outcome.spoken,
    ));

    // 5. Guardians: whether the record reached them.
    if (written == null) {
      legs.add(const LegResult(SosLeg.guardians, LegOutcome.failed,
          detail: 'You are not signed in on this phone.'));
    } else if (guardianCount == 0) {
      legs.add(const LegResult(SosLeg.guardians, LegOutcome.notConfigured));
    } else {
      legs.add(await _alertGuardians(written));
    }

    // Sorted back into the order the receipt reads best in.
    legs.sort((a, b) =>
        SosLeg.values.indexOf(a.leg).compareTo(SosLeg.values.indexOf(b.leg)));
    return SosReceipt(legs, eventId: eventId);
  }

  /// Stopped by the user after the countdown, before anyone was called.
  ///
  /// Recorded like a cancelled countdown, with where it stopped, and without
  /// the position: nothing was sent, so nothing is kept.
  SosReceipt _cancelledBeforeCall(String? userId, List<LegResult> legs) {
    unawaited(recordCancellation(userId, stage: 'before-call'));
    return SosReceipt([
      ...legs,
      const LegResult(SosLeg.call, LegOutcome.cancelled),
      const LegResult(SosLeg.location, LegOutcome.cancelled),
      const LegResult(SosLeg.guardians, LegOutcome.cancelled),
    ]);
  }

  /// Rings one contact and reports whether the dialler took the number.
  ///
  /// "Done" means the dialler opened, not that anyone answered - the phone
  /// cannot know that, and the receipt's wording is chosen not to claim it.
  Future<LegResult> call(EmergencyContact contact) async {
    final number = contact.dialable;
    if (number.isEmpty) {
      return LegResult(SosLeg.call, LegOutcome.notConfigured,
          detail: contact.name);
    }
    try {
      final ok = await _dial(Uri(scheme: 'tel', path: number));
      return LegResult(SosLeg.call, ok ? LegOutcome.done : LegOutcome.failed,
          detail: contact.name);
    } catch (_) {
      return LegResult(SosLeg.call, LegOutcome.failed, detail: contact.name);
    }
  }

  /// Opens the messaging app with every contact and [body] filled in.
  ///
  /// The one channel a phone can fan out on by itself. The user still
  /// presses Send; no app may send a text unasked, and for an emergency
  /// text that is the right way round. Returns false if no messaging app
  /// took it.
  Future<bool> textAll(List<EmergencyContact> contacts, String body) async {
    if (contacts.isEmpty) return false;
    try {
      return await _dial(smsLink(contacts, body, ios: _isIos));
    } catch (_) {
      return false;
    }
  }

  final bool _isIos = !kIsWeb && Platform.isIOS;

  Future<LegResult> _alertGuardians(Future<void> written) async =>
      LegResult(SosLeg.guardians, await _confirmed(written));

  /// Whether the server took [write] within [guardianBudget].
  Future<LegOutcome> _confirmed(Future<void> write) async {
    try {
      await write.timeout(guardianBudget);
      return LegOutcome.done;
    } on TimeoutException {
      // Queued on the device. Not a success, and said so; not a failure
      // either, because giving up now would be wrong too.
      return LegOutcome.pending;
    } catch (_) {
      // Refused, or the SDK threw. Either way the user is told.
      return LegOutcome.failed;
    }
  }

  /// The user said they are okay after the call.
  ///
  /// Not a cancellation: "cancelled" means nothing happened, and here a call
  /// was made. The event is marked resolved, by the user, which is what the
  /// guardian's phone and the dashboard show. [LegOutcome.notConfigured]
  /// when there was no event to mark - nobody was signed in.
  Future<LegOutcome> resolve(String? eventId) async {
    if (eventId == null) return LegOutcome.notConfigured;
    final update = _update(eventId, const {
      'status': 'resolved',
      'resolvedBy': 'user',
    });
    return _confirmed(update);
  }

  /// Records that an armed SOS was stopped before anything happened.
  ///
  /// Kept because the review timeline treats a cancelled SOS as a signal: it
  /// either means the countdown saved someone from a false alarm, or the button
  /// is too easy to hit.
  ///
  /// [stage] says how far it had gone, when it was past the countdown.
  Future<void> recordCancellation(String? userId, {String? stage}) async {
    if (userId == null || userId.isEmpty) return;
    try {
      await _write({
        'userId': userId,
        'cancelled': true,
        if (stage != null) 'stage': stage,
      }).timeout(guardianBudget);
    } catch (_) {
      // A cancellation that could not be logged is not worth telling the user
      // about; nothing was sent either way.
    }
  }
}
