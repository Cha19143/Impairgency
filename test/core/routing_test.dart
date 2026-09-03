import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/routes.dart';

void main() {
  const anon = SessionState();
  const admin = SessionState(signedIn: true, isAdmin: true);
  const guardian = SessionState(signedIn: true, isGuardian: true);
  final settled = SessionState(
    signedIn: true,
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
      const staff = SessionState(signedIn: true);
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
      const fresh = SessionState(signedIn: true);
      expect(fresh.resumeAt, Routes.createAccount);
    });

    test('a killed app returns to the first incomplete step', () {
      const midway = SessionState(
        signedIn: true,
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
