import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/session_store.dart';
import 'package:impairgency/core/sos/sos_receipt.dart';

/// The three flow guarantees the plan promised, asserted rather than hoped
/// about: #57 resume, #59 skip everything and still get an SOS, #60 an SOS with
/// nobody configured tells the truth.
void main() {
  group('#57 — setup resumes at the first incomplete step after a kill', () {
    Future<AppSession> relaunch(SessionStore store) async {
      // A fresh session over the same store is exactly what a relaunch is.
      final session = AppSession(store: store);
      await session.load();
      session.update(SessionState(
        uid: 'u1',
        signedIn: true,
        safetyAcknowledged: session.state.safetyAcknowledged,
        completedSteps: session.state.completedSteps,
      ));
      return session;
    }

    test('a kill halfway through returns to the step that was next', () async {
      final store = InMemorySessionStore(acknowledged: true);
      await store.markStepComplete(Routes.createAccount);
      await store.markStepComplete(Routes.profile);
      await store.markStepComplete(Routes.preferences);

      final session = await relaunch(store);
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.home, session: session.state),
        Routes.emergencyContact,
        reason: 'starting from scratch would be punishing',
      );
    });

    test('every partial state resumes somewhere sensible', () async {
      // Walk the flow one step at a time and check each relaunch lands on the
      // next incomplete step, never earlier and never further on.
      final store = InMemorySessionStore(acknowledged: true);
      for (final step in Routes.onboardingFlow) {
        final session = await relaunch(store);
        expect(session.state.resumeAt, step,
            reason: 'should resume at $step');
        await store.markStepComplete(step);
      }

      final finished = await relaunch(store);
      expect(finished.state.setupComplete, isTrue);
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.home, session: finished.state),
        isNull,
      );
    });

    test('a kill before the safety notice starts there, not in onboarding',
        () async {
      final session = await relaunch(InMemorySessionStore());
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.home, session: session.state),
        Routes.safety,
      );
    });
  });

  group('#59 — skip every skippable step and still reach a working SOS', () {
    test('skipping advances rather than asking again', () async {
      // cprwire's skip left the step incomplete, so a user who skipped was
      // asked the same question on every launch.
      final store = InMemorySessionStore(acknowledged: true);
      for (final step in Routes.onboardingFlow) {
        await store.markStepComplete(step);
      }

      final session = AppSession(store: store);
      await session.load();
      session.update(SessionState(
        uid: 'u1',
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: session.state.completedSteps,
      ));

      expect(session.state.setupComplete, isTrue);
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.sos, session: session.state),
        isNull,
        reason: 'a user who skipped everything can still reach SOS',
      );
    });

    test('the SOS route is reachable with nothing configured at all', () {
      final bare = SessionState(
        uid: 'u1',
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: Routes.onboardingFlow.toSet(),
      );
      expect(bare.contactNumber, isNull);
      expect(bare.guardianCount, 0);
      expect(resolveRedirect(isWeb: false, location: Routes.sos, session: bare),
          isNull);
    });
  });

  group('#60 — an SOS with nobody configured says so', () {
    test('the receipt names the alarm and admits nobody was reached', () {
      // What the engine produces when there is no contact and no guardian.
      const receipt = SosReceipt([
        LegResult(SosLeg.alarm, LegOutcome.done),
        LegResult(SosLeg.call, LegOutcome.notConfigured),
        LegResult(SosLeg.location, LegOutcome.failed,
            detail: 'Your location was not sent, because location sharing is '
                'off.'),
        LegResult(SosLeg.guardians, LegOutcome.notConfigured),
      ]);

      expect(receipt.anyoneReached, isFalse);
      expect(receipt.headline, 'Nobody was reached');
      expect(receipt.spoken, startsWith('Nobody was reached.'));
      expect(receipt.spoken, contains('The alarm is sounding.'));
      expect(receipt.spoken, contains('No emergency contact is saved'));
      expect(receipt.spoken, contains('You have no guardian'));
    });

    test('it never implies anything was delivered', () {
      const receipt = SosReceipt([
        LegResult(SosLeg.alarm, LegOutcome.done),
        LegResult(SosLeg.call, LegOutcome.notConfigured),
        LegResult(SosLeg.location, LegOutcome.failed),
        LegResult(SosLeg.guardians, LegOutcome.notConfigured),
      ]);

      final said = receipt.spoken.toLowerCase();
      for (final claim in [
        'on the way',
        'help is coming',
        'has been sent',
        'someone will',
      ]) {
        expect(said, isNot(contains(claim)), reason: claim);
      }
    });
  });
}
