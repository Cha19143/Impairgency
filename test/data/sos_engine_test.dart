import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/contacts/emergency_contact.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/core/sos/sos_receipt.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/data/sos_engine.dart';

class RecordingSpeaker implements Speaker {
  final List<String> said = [];
  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;
  @override
  Future<void> repeat() async {}
  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);
  @override
  Future<void> stop() async {}
}

class FixedLocation implements LocationSource {
  const FixedLocation(this.state, {this.fix});
  final LocationAvailability state;
  final LocationFix? fix;
  @override
  Future<LocationAvailability> availability() async => state;
  @override
  Future<LocationAvailability> requestPermission() async => state;
  @override
  Future<LocationFix?> currentFix({Duration timeout = Duration.zero}) async =>
      fix;
  @override
  Future<LocationFix?> lastKnownFix() async => fix;
}

/// The legs, each replaced by something the test controls.
class Harness {
  Harness({
    this.dialResult = true,
    this.dialThrows = false,
    this.writeThrows = false,
    this.writeHangs = false,
    LocationSource? location,
  }) : location = location ?? const FixedLocation(LocationAvailability.denied);

  final bool dialResult;
  final bool dialThrows;
  final bool writeThrows;
  final bool writeHangs;
  final LocationSource location;
  final speaker = RecordingSpeaker();
  final dialled = <Uri>[];
  final written = <Map<String, Object?>>[];

  late final engine = SosEngine(
    speaker: speaker,
    location: location,
    locationBudget: Duration.zero,
    guardianBudget: const Duration(milliseconds: 50),
    dial: (uri) async {
      if (dialThrows) throw StateError('no dialler');
      dialled.add(uri);
      return dialResult;
    },
    writeEvent: (event) async {
      if (writeThrows) throw StateError('permission denied');
      if (writeHangs) await Completer<void>().future;
      written.add(event);
    },
  );
}

void main() {
  group('the call leg', () {
    test('dials the saved number, as a tel: link', () async {
      final h = Harness();
      final receipt = await h.engine.fire(
        userId: 'u1',
        contacts: const [
          EmergencyContact(name: 'Mum', number: '+63 917 000 0000'),
        ],
        guardianCount: 0,
      );
      expect(h.dialled.single.scheme, 'tel');
      expect(h.dialled.single.path, '+639170000000',
          reason: 'spaces would reach the dialler as %20');
      expect(h.dialled.single.toString(), 'tel:+639170000000');
      expect(receipt.of(SosLeg.call)!.outcome, LegOutcome.done);
      expect(receipt.spoken, contains('Called Mum.'));
    });

    test('no contact means nobody is dialled and the receipt says so',
        () async {
      final h = Harness();
      final receipt =
          await h.engine.fire(userId: 'u1', guardianCount: 0);
      expect(h.dialled, isEmpty);
      expect(receipt.of(SosLeg.call)!.outcome, LegOutcome.notConfigured);
      expect(receipt.spoken, contains('No emergency contact is saved'));
    });

    test('a dialler that refuses is reported as a call that did not connect',
        () async {
      final h = Harness(dialResult: false);
      final receipt = await h.engine.fire(
          userId: 'u1',
          contacts: const [EmergencyContact(name: 'Mum', number: '0917')],
          guardianCount: 0);
      expect(receipt.of(SosLeg.call)!.outcome, LegOutcome.failed);
      expect(receipt.spoken, contains('did not connect'));
    });

    test('a dialler that throws does not take the SOS down', () async {
      final h = Harness(dialThrows: true);
      final receipt = await h.engine.fire(
          userId: 'u1',
          contacts: const [EmergencyContact(name: 'Mum', number: '0917')],
          guardianCount: 0);
      expect(receipt.of(SosLeg.alarm)!.succeeded, isTrue);
      expect(receipt.of(SosLeg.call)!.outcome, LegOutcome.failed);
    });
  });

  group('several contacts - the calling order', () {
    test('only the first is rung by the legs; the rest are offered after',
        () async {
      // A phone places one call at a time.
      final h = Harness();
      final receipt = await h.engine.fire(
        userId: 'u1',
        contacts: const [
          EmergencyContact(name: 'Mum', number: '0917'),
          EmergencyContact(name: 'Dad', number: '0918'),
        ],
        guardianCount: 0,
      );
      expect(h.dialled.map((u) => u.path), ['0917']);
      expect(receipt.calls.single.detail, 'Mum');

      final next = await h.engine.call(
          const EmergencyContact(name: 'Dad', number: '0918'));
      expect(h.dialled.map((u) => u.path), ['0917', '0918']);
      final chained = receipt.withCall(next);
      expect(chained.calls.map((c) => c.detail), ['Mum', 'Dad']);
      expect(chained.spoken, contains('Called Dad.'));
    });

    test('every contact is written on the event for the guardian', () async {
      final h = Harness();
      await h.engine.fire(
        userId: 'u1',
        contacts: const [
          EmergencyContact(name: 'Mum', number: '0917'),
          EmergencyContact(name: 'Dad', number: '0918'),
        ],
        guardianCount: 1,
      );
      final contacts = h.written.single['contacts'] as List;
      expect(contacts, hasLength(2));
      expect((contacts[1] as Map)['name'], 'Dad');
      expect((h.written.single['contact'] as Map)['name'], 'Mum',
          reason: 'the old single field still names the first');
    });

    test('a text to everyone opens the messaging app with all numbers',
        () async {
      final h = Harness();
      final ok = await h.engine.textAll(
        const [
          EmergencyContact(name: 'Mum', number: '0917'),
          EmergencyContact(name: 'Dad', number: '+63 918'),
        ],
        'Emergency. I need help.',
      );
      expect(ok, isTrue);
      final uri = h.dialled.single;
      expect(uri.scheme, 'sms');
      expect(uri.toString(), contains('0917'));
      expect(uri.path, '0917;+63918');
      expect(uri.queryParameters['body'], 'Emergency. I need help.');
    });

    test('with nobody to text, nothing opens', () async {
      final h = Harness();
      expect(await h.engine.textAll(const [], 'x'), isFalse);
      expect(h.dialled, isEmpty);
    });
  });

  group('the alarm', () {
    test('sounds first, before anything that could wait', () async {
      final h = Harness();
      await h.engine.fire(userId: 'u1', guardianCount: 0);
      expect(h.speaker.said.first, contains('Emergency'));
    });
  });

  group('the guardian leg', () {
    test('writes the event, and says the guardian was told', () async {
      final h = Harness();
      final receipt =
          await h.engine.fire(userId: 'u1', guardianCount: 1);
      expect(h.written.single['userId'], 'u1');
      expect(h.written.single['cancelled'], false);
      expect(receipt.of(SosLeg.guardians)!.outcome, LegOutcome.done);
    });

    test('with no guardian the event is still recorded, honestly', () async {
      // An administrator reviews it, and a guardian paired afterwards can
      // still see it. Only the wording changes.
      final h = Harness();
      final receipt =
          await h.engine.fire(userId: 'u1', guardianCount: 0);
      await Future<void>.delayed(Duration.zero);
      expect(h.written, hasLength(1));
      expect(receipt.of(SosLeg.guardians)!.outcome, LegOutcome.notConfigured);
      expect(receipt.anyoneReached, isFalse);
    });

    test('offline, the write does not hang the SOS forever', () async {
      // A Firestore write completes on server acknowledgement. With no
      // signal, that is never - and the flow sat on "Calling for help…".
      final h = Harness(writeHangs: true);
      final receipt = await h.engine
          .fire(userId: 'u1', guardianCount: 1)
          .timeout(const Duration(seconds: 2));
      final leg = receipt.of(SosLeg.guardians)!;
      expect(leg.outcome, LegOutcome.pending);
      expect(leg.succeeded, isFalse);
      expect(receipt.anyoneReached, isFalse,
          reason: 'queued is not reached');
      expect(receipt.spoken, contains('waiting for a connection'));
    });

    test('a refused write is a failure, named', () async {
      final h = Harness(writeThrows: true);
      final receipt =
          await h.engine.fire(userId: 'u1', guardianCount: 1);
      expect(receipt.of(SosLeg.guardians)!.outcome, LegOutcome.failed);
      expect(receipt.spoken, contains('could not be reached'));
    });

    test('nobody signed in means no event, and the receipt says why',
        () async {
      // Never written under a placeholder id: the rules would refuse it
      // silently, and the receipt would have claimed a guardian was told.
      final h = Harness();
      final receipt =
          await h.engine.fire(userId: null, guardianCount: 1);
      expect(h.written, isEmpty);
      expect(receipt.of(SosLeg.guardians)!.outcome, LegOutcome.failed);
      expect(receipt.spoken, contains('not signed in'));
    });

    test('the event carries the contact and the position', () async {
      final h = Harness(
        location: FixedLocation(
          LocationAvailability.ready,
          fix: LocationFix(
              latitude: 14.6, longitude: 121.0, accuracyMetres: 12, at: DateTime.now()),
        ),
      );
      await h.engine.fire(
          userId: 'u1',
          contacts: const [EmergencyContact(name: 'Mum', number: '0917')],
          guardianCount: 1);
      final event = h.written.single;
      expect(event['lat'], 14.6);
      expect((event['contact'] as Map)['number'], '0917');
      expect(event['locationSummary'], 'Your location was sent.');
    });
  });

  group('the location leg', () {
    test('a refused permission is a named failure, not a crash', () async {
      final h = Harness(
          location: const FixedLocation(LocationAvailability.deniedForever));
      final receipt =
          await h.engine.fire(userId: 'u1', guardianCount: 0);
      expect(receipt.of(SosLeg.location)!.outcome, LegOutcome.failed);
      expect(receipt.spoken, contains('blocked for this app'));
    });
  });

  group('cancellation', () {
    test('is recorded when there is an account, and skipped when not',
        () async {
      final h = Harness();
      await h.engine.recordCancellation('u1');
      await h.engine.recordCancellation(null);
      expect(h.written, hasLength(1));
      expect(h.written.single['cancelled'], true);
    });
  });

  group('cancel after the countdown, before the call', () {
    // The alarm and the position take seconds before anyone is rung. A
    // "cancel" in those seconds stops the SOS; after the dialler opens it
    // cannot, and the app is behind the call anyway.
    test('cancel between the alarm and the call stops the call, and the '
        'receipt says so', () async {
      final finding = Completer<LocationFix?>();
      final h = Harness(location: _Finding(finding));
      final cancelled = Completer<void>();
      var committed = false;

      final firing = h.engine.fire(
        userId: 'u1',
        contacts: const [EmergencyContact(name: 'Mum', number: '09170000000')],
        guardianCount: 1,
        cancelled: cancelled.future,
        onCommitted: () => committed = true,
      );
      await pumpEventQueue();
      expect(h.speaker.said, [kSosAlarm], reason: 'the alarm sounded');

      cancelled.complete(); // while the position is still being found
      final receipt = await firing;
      await pumpEventQueue();

      expect(h.dialled, isEmpty);
      expect(committed, isFalse);
      expect(receipt.cancelled, isTrue);
      expect(receipt.anyoneReached, isFalse);
      expect(receipt.headline, 'Cancelled before calling');
      expect(receipt.of(SosLeg.call)!.outcome, LegOutcome.cancelled);
      expect(receipt.of(SosLeg.guardians)!.outcome, LegOutcome.cancelled);
      expect(receipt.spoken, contains('You said cancel, so nobody was called.'));

      // Recorded as a cancellation, where it stopped, and without a position:
      // nothing was sent, so nothing is kept.
      expect(h.written.single,
          {'userId': 'u1', 'cancelled': true, 'stage': 'before-call'});
    });

    test('a cancel during the alarm itself stops it there', () async {
      final h = Harness();
      final cancelled = Completer<void>()..complete();
      final receipt = await h.engine.fire(
        userId: 'u1',
        contacts: const [EmergencyContact(name: 'Mum', number: '09170000000')],
        guardianCount: 0,
        cancelled: cancelled.future,
      );
      expect(h.dialled, isEmpty);
      expect(receipt.cancelled, isTrue);
    });

    test('once committed, it calls as before', () async {
      final h = Harness();
      var committed = false;
      final receipt = await h.engine.fire(
        userId: 'u1',
        contacts: const [EmergencyContact(name: 'Mum', number: '09170000000')],
        guardianCount: 1,
        cancelled: Completer<void>().future,
        onCommitted: () => committed = true,
      );
      expect(committed, isTrue);
      expect(h.dialled, hasLength(1));
      expect(receipt.cancelled, isFalse);
    });
  });
}

/// A position that arrives when the test says.
class _Finding implements LocationSource {
  _Finding(this.fix);
  final Completer<LocationFix?> fix;
  @override
  Future<LocationAvailability> availability() async =>
      LocationAvailability.ready;
  @override
  Future<LocationAvailability> requestPermission() async =>
      LocationAvailability.ready;
  @override
  Future<LocationFix?> currentFix({Duration timeout = Duration.zero}) =>
      fix.future;
  @override
  Future<LocationFix?> lastKnownFix() async => null;
}
