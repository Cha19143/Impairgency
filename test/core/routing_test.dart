import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/routes.dart';

void main() {
  // Every mobile fixture acknowledges the safety notice, because the notice
  // gates everything before it and would otherwise be the only thing these
  // tests measured. The notice's own behaviour is asserted in its own group.
  const anon = SessionState(safetyAcknowledged: true);
  const admin = SessionState(signedIn: true, isAdmin: true);
  const guardian =
      SessionState(signedIn: true, isGuardian: true, safetyAcknowledged: true);
  final settled = SessionState(
    signedIn: true,
    safetyAcknowledged: true,
    completedSteps: Routes.onboardingFlow.toSet(),
  );

  group('the platform split (requirements: admin dashboard is web)', () {
    test('web serves the dashboard and nothing else', () {
      expect(
        resolveRedirect(isWeb: true, location: Routes.home, session: settled),
        Routes.adminRoot,
      );
      expect(
        resolveRedirect(
            isWeb: true, location: Routes.welcome, session: settled),
        Routes.adminRoot,
      );
    });

    test('mobile cannot reach the dashboard, signed in or not', () {
      for (final session in [anon, settled, admin]) {
        expect(
          resolveRedirect(
              isWeb: false, location: Routes.adminOverview, session: session),
          Routes.welcome,
        );
      }
    });
  });

  group('the auth guard the old router did not have', () {
    test('an anonymous visitor to /admin lands on sign-in', () {
      expect(
        resolveRedirect(
            isWeb: true, location: Routes.adminOverview, session: anon),
        Routes.adminSignIn,
      );
    });

    test('a signed-in non-admin cannot reach the dashboard', () {
      const staff = SessionState(signedIn: true, safetyAcknowledged: true);
      expect(
        resolveRedirect(
            isWeb: true, location: Routes.adminOverview, session: staff),
        Routes.adminSignIn,
      );
    });

    test('an admin passes through', () {
      expect(
        resolveRedirect(
            isWeb: true, location: Routes.adminOverview, session: admin),
        isNull,
      );
    });

    test('anonymous mobile users are held in onboarding', () {
      expect(
        resolveRedirect(isWeb: false, location: Routes.home, session: anon),
        Routes.welcome,
      );
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.createAccount, session: anon),
        isNull,
      );
    });
  });

  group('onboarding resumes where it stopped', () {
    test('a fresh account starts at step one', () {
      const fresh = SessionState(signedIn: true, safetyAcknowledged: true);
      expect(fresh.resumeAt, Routes.createAccount);
    });

    test('a killed app returns to the first incomplete step', () {
      const midway = SessionState(
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: {Routes.createAccount, Routes.preferences},
      );
      expect(midway.resumeAt, Routes.emergencyContact);
      expect(
        resolveRedirect(isWeb: false, location: Routes.home, session: midway),
        Routes.emergencyContact,
      );
    });

    test('skipped steps still count as done, so skipping is not a trap', () {
      // Preferences, guardian and device are skippable. Skipping must advance.
      final skipper = SessionState(
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: Routes.onboardingFlow.toSet(),
      );
      expect(skipper.setupComplete, isTrue);
      expect(skipper.resumeAt, Routes.home);
    });

    test('finished setup cannot fall back into onboarding', () {
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.createAccount, session: settled),
        Routes.home,
      );
      expect(
        resolveRedirect(isWeb: false, location: Routes.home, session: settled),
        isNull,
      );
    });

    test('the completion screen has no route back to sign-in', () {
      // cprwire's All Set screen offered "GO TO LOGIN" seconds after
      // registering. There is no such destination now.
      expect(Routes.onboardingFlow.last, Routes.allSet);
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.welcome, session: settled),
        Routes.home,
      );
    });
  });

  group('the safety notice comes first (§7)', () {
    const fresh = SessionState();

    test('a first run hears it before anything else', () {
      for (final target in [
        Routes.welcome,
        Routes.home,
        Routes.createAccount,
        Routes.guardianHome,
      ]) {
        expect(
          resolveRedirect(isWeb: false, location: target, session: fresh),
          Routes.safety,
          reason: '$target should be gated by the safety notice',
        );
      }
    });

    test('it gates a signed-in user too, not just a new install', () {
      const returning = SessionState(signedIn: true);
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.home, session: returning),
        Routes.safety,
      );
    });

    test('the notice screen itself is reachable while unacknowledged', () {
      expect(
        resolveRedirect(isWeb: false, location: Routes.safety, session: fresh),
        isNull,
      );
    });

    test('it stays reachable after acknowledgement', () {
      // The notice says "you can hear this again at any time from the main
      // screen", so the router has to honour that rather than bounce them home.
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.safety, session: settled),
        isNull,
      );
    });

    test('acknowledging it lets the user through', () {
      expect(
        resolveRedirect(isWeb: false, location: Routes.home, session: anon),
        Routes.welcome,
        reason: 'gated by sign-in now, not by the notice',
      );
    });

    test('it does not gate the web dashboard', () {
      // Admins are not the people the notice is written for, and it would be
      // one more thing between an unauthenticated visitor and the sign-in page.
      expect(
        resolveRedirect(
            isWeb: true, location: Routes.adminOverview, session: admin),
        isNull,
      );
    });
  });

  group('guardians', () {
    test('land in the guardian app, not the user app', () {
      expect(
        resolveRedirect(isWeb: false, location: Routes.home, session: guardian),
        Routes.guardianHome,
      );
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.guardianAccept, session: guardian),
        isNull,
      );
    });
  });
}
