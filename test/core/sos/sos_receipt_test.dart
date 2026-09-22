import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/sos/sos_countdown.dart';
import 'package:impairgency/core/sos/sos_receipt.dart';

SosReceipt receipt({
  LegOutcome alarm = LegOutcome.done,
  LegOutcome call = LegOutcome.done,
  LegOutcome location = LegOutcome.done,
  LegOutcome guardians = LegOutcome.done,
  String? callDetail = 'Mum',
  String? locationDetail = 'Your location was sent.',
  String? guardianDetail,
}) =>
    SosReceipt([
      LegResult(SosLeg.alarm, alarm),
      LegResult(SosLeg.call, call, detail: callDetail),
      LegResult(SosLeg.location, location, detail: locationDetail),
      LegResult(SosLeg.guardians, guardians, detail: guardianDetail),
    ]);

void main() {
  group('the rule the file exists for: never imply success', () {
    test('says plainly when nobody was reached', () {
      final r = receipt(
        call: LegOutcome.notConfigured,
        guardians: LegOutcome.notConfigured,
        callDetail: null,
      );
      expect(r.anyoneReached, isFalse);
      expect(r.headline, 'Nobody was reached');
      expect(r.spoken, startsWith('Nobody was reached.'));
    });

    test('a failed call is never described as a call', () {
      final r = receipt(call: LegOutcome.failed);
      expect(r.spoken, contains('did not connect'));
      expect(r.spoken, isNot(contains('Called Mum.')));
    });

    test('an SOS with nothing configured still says the alarm sounded',
        () {
      // The one leg that needs nothing. It has to be reported, because it is
      // the only thing that happened.
      final r = receipt(
        call: LegOutcome.notConfigured,
        guardians: LegOutcome.notConfigured,
        location: LegOutcome.notConfigured,
        callDetail: null,
        locationDetail: 'Your location was not sent, because location sharing '
            'is off.',
      );
      expect(r.spoken, contains('The alarm is sounding.'));
      expect(r.spoken, contains('nobody was called'));
      expect(r.spoken, contains('no guardian'));
    });

    test('never says help is on the way', () {
      for (final outcome in LegOutcome.values) {
        final r = receipt(call: outcome, guardians: outcome);
        final said = r.spoken.toLowerCase();
        expect(said, isNot(contains('on the way')));
        expect(said, isNot(contains('help is coming')));
        expect(said, isNot(contains('do not worry')));
      }
    });
  });

  group('telling apart "failed" from "there was nothing to try"', () {
    test('no contact saved reads differently from a call that failed', () {
      final missing = receipt(call: LegOutcome.notConfigured, callDetail: null);
      final failed = receipt(call: LegOutcome.failed);

      expect(missing.spoken, contains('No emergency contact is saved'));
      expect(failed.spoken, contains('did not connect'));
      expect(missing.spoken, isNot(contains('did not connect')));
    });

    test('no guardian reads differently from a guardian not reached', () {
      final missing = receipt(guardians: LegOutcome.notConfigured);
      final failed = receipt(guardians: LegOutcome.failed);

      expect(missing.spoken, contains('You have no guardian'));
      expect(failed.spoken, contains('could not be reached'));
    });

    test('an alert queued for a connection is neither reached nor failed', () {
      final queued = receipt(guardians: LegOutcome.pending, call: LegOutcome.failed);
      expect(queued.anyoneReached, isFalse);
      expect(queued.headline, 'Nobody was reached');
      expect(queued.spoken, contains('waiting for a connection'));
      expect(queued.spoken, isNot(contains('could not be reached')));
    });
  });

  group('several calls - the fan-out, one call at a time', () {
    test('a second call is added in reading order and counted as reached', () {
      final first = receipt(call: LegOutcome.failed);
      expect(first.anyoneReached, isTrue, reason: 'guardian was told');
      final noone = receipt(call: LegOutcome.failed, guardians: LegOutcome.notConfigured);
      expect(noone.anyoneReached, isFalse);

      final chained = noone.withCall(
          const LegResult(SosLeg.call, LegOutcome.done, detail: 'Dad'));
      expect(chained.calls.map((c) => c.detail), ['Mum', 'Dad']);
      expect(chained.anyoneReached, isTrue);
      expect(chained.legs.map((l) => l.leg), [
        SosLeg.alarm,
        SosLeg.call,
        SosLeg.call,
        SosLeg.location,
        SosLeg.guardians,
      ]);
      expect(chained.spoken, contains('The call to Mum did not connect.'));
      expect(chained.spoken, contains('Called Dad.'));
    });
  });

  group('what it leads with', () {
    test('reaching someone comes first, because that is what matters', () {
      final r = receipt();
      expect(r.spoken, startsWith('Your contact answered and your guardian was told.'));
    });

    test('names only who was actually reached', () {
      expect(receipt(guardians: LegOutcome.failed).spoken,
          startsWith('Your contact answered.'));
      expect(receipt(call: LegOutcome.failed).spoken,
          startsWith('Your guardian was told.'));
    });
  });

  group('location', () {
    test('passes the location policy sentence through unchanged', () {
      // That sentence already distinguishes the four causes and never calls a
      // stale fix current. Rewriting it here would lose that.
      const prose = 'Your last known location, from 20 minutes ago, was sent.';
      final r = receipt(location: LegOutcome.done, locationDetail: prose);
      expect(r.spoken, contains(prose));
    });

    test('falls back to a truthful default when there is no prose', () {
      final r = receipt(location: LegOutcome.failed, locationDetail: null);
      expect(r.spoken, contains('Your location was not sent.'));
    });
  });

  group('what is heard and what is read cannot drift', () {
    test('every line on screen is a line the receipt speaks', () {
      final r = receipt(call: LegOutcome.failed, guardians: LegOutcome.notConfigured);
      for (final leg in r.legs) {
        expect(r.spoken, contains(r.sentenceFor(leg)),
            reason: '${leg.leg} is rendered but not spoken');
      }
    });
  });

  group('every leg is reported', () {
    test('the receipt mentions all four, whatever happened', () {
      final r = receipt(
        alarm: LegOutcome.failed,
        call: LegOutcome.failed,
        location: LegOutcome.failed,
        guardians: LegOutcome.failed,
        locationDetail: null,
      );
      expect(r.legs, hasLength(4));
      expect(r.everythingWorked, isFalse);
      for (final leg in SosLeg.values) {
        expect(r.of(leg), isNotNull, reason: '$leg missing from the receipt');
      }
    });
  });

  group('the arming countdown', () {
    test('counts down aloud, because silence tells a blind user nothing', () {
      expect(armingAnnouncement(3, contactName: 'Mum'), 'Calling Mum in 3.');
      expect(armingAnnouncement(1, contactName: 'Mum'), 'Calling Mum in 1.');
      expect(armingAnnouncement(0), 'Calling now.');
    });

    test('says "for help" when there is no contact to name', () {
      expect(armingAnnouncement(3), 'Calling for help in 3.');
      expect(armingAnnouncement(3, contactName: '   '), contains('for help'));
    });

    test('says how to stop it, since a button cannot be found by touch alone',
        () {
      expect(kArmingHint, contains('cancel'));
      expect(kArmingHint, contains('touch the screen anywhere'));
    });

    test('cancelling confirms that nothing happened', () {
      // The whole point of the countdown: cancel has to mean cancel.
      expect(kCancelledAnnouncement, contains('Nothing was sent'));
      expect(kCancelledAnnouncement, contains('nobody was called'));
    });

    test('is long enough to say "no" and short enough to be an emergency', () {
      expect(kArmingDuration.inSeconds, inInclusiveRange(2, 5));
    });
  });

  group('cancelled after the countdown', () {
    const receipt = SosReceipt([
      LegResult(SosLeg.alarm, LegOutcome.done),
      LegResult(SosLeg.call, LegOutcome.cancelled),
      LegResult(SosLeg.location, LegOutcome.cancelled),
      LegResult(SosLeg.guardians, LegOutcome.cancelled),
    ]);

    test('says the user stopped it, not that something failed', () {
      expect(receipt.cancelled, isTrue);
      expect(receipt.headline, 'Cancelled before calling');
      expect(receipt.spoken, startsWith('Cancelled before calling.'));
      expect(receipt.spoken, isNot(contains('did not connect')));
      expect(receipt.spoken, isNot(contains('could not be reached')));
    });

    test('names each leg that was not attempted, and why', () {
      expect(receipt.sentenceFor(receipt.of(SosLeg.call)!),
          'You said cancel, so nobody was called.');
      expect(receipt.sentenceFor(receipt.of(SosLeg.location)!),
          'Your location was not sent.');
      expect(receipt.sentenceFor(receipt.of(SosLeg.guardians)!),
          'You said cancel, so your guardian was not alerted.');
    });

    test('reached nobody, so trying again stays on offer', () {
      expect(receipt.anyoneReached, isFalse);
    });
  });
}
