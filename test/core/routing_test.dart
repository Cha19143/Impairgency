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

    test('a signed-in admin is moved off the sign-in page', () {
      // The bug this exists for: the guard was right that the account was
      // allowed and said nothing about where to go, so go_router kept them on
      // the form they had just successfully filled in.
      expect(
        resolveRedirect(
            isWeb: true, location: Routes.adminSignIn, session: admin),
        Routes.adminOverview,
      );
    });

    test('every web location resolves somewhere sensible for every session',
        () {
      // A matrix rather than one case each, because the two bugs found so far
      // were both a location that was never paired with a session state.
      const locations = [
        Routes.adminRoot,
        Routes.adminSignIn,
        Routes.adminOverview,
        Routes.adminUsers,
        Routes.adminHealth,
        Routes.adminAccessibility,
      ];
      final sessions = {
        'anonymous': anon,
        'signed in, not admin': const SessionState(signedIn: true),
        'admin': admin,
      };

      sessions.forEach((label, session) {
        for (final location in locations) {
          final target =
              resolveRedirect(isWeb: true, location: location, session: session);

          // Never bounce a visitor to the page they are already on: that is a
          // no-op, and it looks to the user like nothing happened.
          expect(target, isNot(location),
              reason: '$label at $location redirects to itself');

          if (session.isAdmin) {
            // An admin never lands on sign-in, and never sits on the bare root.
            expect(target, isNot(Routes.adminSignIn), reason: '$label $location');
            if (location == Routes.adminRoot ||
                location == Routes.adminSignIn) {
              expect(target, Routes.adminOverview, reason: '$label $location');
            } else {
              expect(target, isNull, reason: '$label $location');
            }
          } else {
            // Everyone else ends up at sign-in, or is already there - in which
            // case the answer is null, not a redirect to where they already
            // are. The sign-in screen explains the not-an-admin case itself.
            expect(target ?? location, Routes.adminSignIn,
                reason: '$label $location');
            if (location == Routes.adminSignIn) {
              expect(target, isNull, reason: '$label $location');
            }
          }
        }
      });
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

  group('the way back in', () {
    test('an anonymous user may reach sign-in', () {
      // Before this route existed the welcome screen's Sign in button led to
      // Create your account, and a returning user had nowhere to go: Firebase
      // told them the email was taken and to sign in instead, which was the
      // button they had pressed.
      expect(
        resolveRedirect(isWeb: false, location: Routes.signIn, session: anon),
        isNull,
      );
    });

    test('signing in is not a step of setting up', () {
      expect(Routes.onboardingFlow, isNot(contains(Routes.signIn)));
      const fresh = SessionState(signedIn: true, safetyAcknowledged: true);
      expect(fresh.resumeAt, Routes.createAccount);
    });

    test('a settled user who lands on it is moved on', () {
      // Otherwise the router leaves them looking at a sign-in form for the
      // account they are already using - the admin dashboard's old bug, on
      // the other platform.
      expect(
        resolveRedirect(isWeb: false, location: Routes.signIn, session: settled),
        Routes.home,
      );
    });

    test('a half-finished user who lands on it goes back to their step', () {
      const midway = SessionState(
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: {
          Routes.createAccount,
          Routes.profile,
          Routes.preferences,
        },
      );
      expect(
        resolveRedirect(isWeb: false, location: Routes.signIn, session: midway),
        Routes.emergencyContact,
      );
    });

    test('the safety notice still comes first', () {
      const unwarned = SessionState();
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.signIn, session: unwarned),
        Routes.safety,
      );
    });

    test('it does not exist on web', () {
      for (final session in [anon, settled]) {
        expect(
          resolveRedirect(isWeb: true, location: Routes.signIn, session: session),
          Routes.adminRoot,
        );
      }
    });

    test('signing out is behind the account, not in front of it', () {
      // /settings/sign-out is not a signed-out route: reaching it without an
      // account would be a confirmation screen for nothing.
      expect(
        resolveRedirect(isWeb: false, location: Routes.signOut, session: anon),
        Routes.welcome,
      );
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.signOut, session: settled),
        isNull,
      );
    });
  });

  group('the doors added for the tester', () {
    test('choosing a role, resetting a password and registering as a guardian '
        'are reachable signed out', () {
      for (final door in [
        Routes.chooseRole,
        Routes.forgotPassword,
        Routes.guardianRegister,
      ]) {
        expect(
          resolveRedirect(isWeb: false, location: door, session: anon),
          isNull,
          reason: '$door should be reachable without an account',
        );
      }
    });

    test('and are left behind once setup is done', () {
      for (final door in [
        Routes.chooseRole,
        Routes.forgotPassword,
        Routes.guardianRegister,
      ]) {
        expect(
          resolveRedirect(isWeb: false, location: door, session: settled),
          Routes.home,
        );
      }
    });

    test('choosing a role is not a step, so it is never resumed to', () {
      expect(Routes.onboardingFlow, isNot(contains(Routes.chooseRole)));
      expect(Routes.onboardingFlow, isNot(contains(Routes.guardianRegister)));
    });

    test('personal information comes right after the account', () {
      expect(Routes.onboardingFlow[0], Routes.createAccount);
      expect(Routes.onboardingFlow[1], Routes.profile);
    });

    test('a guardian can sign out, and is otherwise kept on their side', () {
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.signOut, session: guardian),
        isNull,
      );
      expect(
        resolveRedirect(isWeb: false, location: Routes.home, session: guardian),
        Routes.guardianHome,
      );
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.guardianHome, session: guardian),
        isNull,
      );
    });

    test('a guardian mid-registration stays on the guardian side', () {
      // The role is cached before the account is created, so the guard sees
      // a guardian from the first auth event.
      //
      // Staying is right: the account exists before the code is checked, and
      // a refused code has to be fixable on the same form. It also means the
      // redirect never moves a guardian whose registration *worked* - that is
      // the screen's onRegistered, and a registration that relied on the
      // redirect is the one the tester reported as doing nothing.
      const registering =
          SessionState(signedIn: true, isGuardian: true, safetyAcknowledged: true);
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.guardianRegister, session: registering),
        isNull,
      );
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.createAccount, session: registering),
        Routes.guardianHome,
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
        completedSteps: {
          Routes.createAccount,
          Routes.profile,
          Routes.preferences,
        },
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

  group('settings reopens the steps that stay useful after setup', () {
    // Emergency contacts, Guardian and Connect a device on the settings
    // screen all point at onboarding routes. Before this, a settled user
    // tapping any of them was bounced straight back to home.
    test('a settled user reaches contacts, guardian and device', () {
      for (final step in Routes.revisitable) {
        expect(
          resolveRedirect(isWeb: false, location: step, session: settled),
          isNull,
          reason: step,
        );
      }
    });

    test('but not the rest of onboarding', () {
      final rest = Routes.onboardingFlow
          .where((step) => !Routes.revisitable.contains(step));
      for (final step in rest) {
        expect(
          resolveRedirect(isWeb: false, location: step, session: settled),
          Routes.home,
          reason: step,
        );
      }
    });

    test('a half-finished user is still held to the order', () {
      const midway = SessionState(
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: {
          Routes.createAccount,
          Routes.profile,
          Routes.preferences,
        },
      );
      expect(
        resolveRedirect(isWeb: false, location: Routes.device, session: midway),
        Routes.emergencyContact,
      );
    });
  });

  group('a new account confirms its email first', () {
    // The tester's made-up email got straight in. A new, unconfirmed account
    // now waits at "Check your email" whatever it asks for.
    final unconfirmed = SessionState(
      signedIn: true,
      safetyAcknowledged: true,
      needsEmailVerification: true,
      completedSteps: const {Routes.createAccount},
    );
    const unconfirmedGuardian = SessionState(
      signedIn: true,
      isGuardian: true,
      safetyAcknowledged: true,
      needsEmailVerification: true,
    );

    test('every other screen sends it to Check your email', () {
      for (final location in [
        Routes.home,
        Routes.scan,
        Routes.profile,
        Routes.settings,
        Routes.welcome,
        Routes.signIn,
      ]) {
        expect(
          resolveRedirect(
              isWeb: false, location: location, session: unconfirmed),
          Routes.verifyEmail,
          reason: location,
        );
      }
      expect(
        resolveRedirect(
            isWeb: false,
            location: Routes.guardianHome,
            session: unconfirmedGuardian),
        Routes.verifyEmail,
      );
    });

    test('it can stay there, and it can still sign out', () {
      for (final session in [unconfirmed, unconfirmedGuardian]) {
        expect(
          resolveRedirect(
              isWeb: false, location: Routes.verifyEmail, session: session),
          isNull,
        );
        expect(
          resolveRedirect(
              isWeb: false, location: Routes.signOut, session: session),
          isNull,
        );
      }
    });

    test('a guardian mid-registration finishes on the form', () {
      // So a refused code is said on the form that sent it.
      expect(
        resolveRedirect(
            isWeb: false,
            location: Routes.guardianRegister,
            session: unconfirmedGuardian),
        isNull,
      );
    });

    test('Create account finishes its own step, then moves on', () {
      const creating = SessionState(
        signedIn: true,
        safetyAcknowledged: true,
        needsEmailVerification: true,
      );
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.createAccount, session: creating),
        isNull,
      );
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.createAccount, session: unconfirmed),
        Routes.verifyEmail,
      );
    });

    test('once confirmed, it is sent on rather than left on the page', () {
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.verifyEmail, session: settled),
        Routes.home,
      );
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.verifyEmail, session: guardian),
        Routes.guardianHome,
      );
      const newUser = SessionState(
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: {Routes.createAccount},
      );
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.verifyEmail, session: newUser),
        Routes.profile,
      );
    });

    test('never redirects a page to itself', () {
      final locations = [
        Routes.verifyEmail,
        Routes.home,
        Routes.guardianHome,
        Routes.guardianRegister,
        Routes.createAccount,
        Routes.signOut,
      ];
      for (final session in [unconfirmed, unconfirmedGuardian, settled]) {
        for (final location in locations) {
          expect(
            resolveRedirect(isWeb: false, location: location, session: session),
            isNot(location),
            reason: location,
          );
        }
      }
    });

    test('the web dashboard is unaffected', () {
      const unconfirmedAdmin =
          SessionState(signedIn: true, isAdmin: true, needsEmailVerification: true);
      expect(
        resolveRedirect(
            isWeb: true,
            location: Routes.adminOverview,
            session: unconfirmedAdmin),
        isNull,
      );
    });

    test('copyWith keeps every field it is not given', () {
      final before = SessionState(
        uid: 'u1',
        signedIn: true,
        isGuardian: true,
        safetyAcknowledged: true,
        completedSteps: const {Routes.createAccount},
        consent: const {'location': true},
        guardianCount: 2,
        needsEmailVerification: true,
      );
      final after = before.copyWith(needsEmailVerification: false);
      expect(after.uid, 'u1');
      expect(after.isGuardian, isTrue);
      expect(after.consent, {'location': true});
      expect(after.guardianCount, 2);
      expect(after.completedSteps, {Routes.createAccount});
      expect(after.needsEmailVerification, isFalse);
    });
  });
}
