import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/safety/safety_notice.dart';
import 'package:impairgency/core/session_store.dart';
import 'package:impairgency/data/prefs_session_store.dart';
import 'package:impairgency/vi/onboarding/onboarding_controller.dart';
import 'package:impairgency/vi/screens/sign_out_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what a returning user has already done', () {
    // The device is the only place onboarding progress was ever written, and a
    // returning user's device does not have it: a second phone, or the same
    // phone after a reinstall, resumes at step one — Create your account — for
    // an account they have just signed in to. These are the facts an account
    // carries with it that say otherwise.

    test('a saved preference means the preferences step is behind them', () {
      expect(
        OnboardingController.stepsEvidencedBy({'screenStaysOn': true}),
        contains(Routes.preferences),
      );
      // False is an answer too. `!= null`, not truthiness.
      expect(
        OnboardingController.stepsEvidencedBy({'screenStaysOn': false}),
        contains(Routes.preferences),
      );
    });

    test('a saved emergency contact means that step is behind them', () {
      expect(
        OnboardingController.stepsEvidencedBy({
          'emergencyContact': {'name': 'Mum', 'number': '+639170000000'},
        }),
        contains(Routes.emergencyContact),
      );
    });

    test('an issued guardian invitation counts, an unissued one does not', () {
      expect(
        OnboardingController.stepsEvidencedBy({'guardianInvited': true}),
        contains(Routes.inviteGuardian),
      );
      expect(
        OnboardingController.stepsEvidencedBy({'guardianInvited': false}),
        isNot(contains(Routes.inviteGuardian)),
      );
    });

    test('an answered device question counts, either way round', () {
      expect(OnboardingController.stepsEvidencedBy({'hasDevice': false}),
          contains(Routes.device));
      expect(OnboardingController.stepsEvidencedBy({'hasDevice': true}),
          contains(Routes.device));
    });

    test('consent proves nothing, because every account is born with it', () {
      // createAccount writes all four consents as false, so the map is present
      // on an account that has never seen the consent screen. Inferring from
      // it would walk a user straight past the one screen that asks what the
      // app may do with where they live.
      expect(
        OnboardingController.stepsEvidencedBy({
          'consent': {'location': false, 'history': false},
        }),
        isNot(contains(Routes.consent)),
      );
    });

    test('an empty account evidences nothing at all', () {
      expect(OnboardingController.stepsEvidencedBy(const {}), isEmpty);
    });
  });

  group('signing out gives the phone back', () {
    test('the device forgets the steps, the profile and the notice', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsSessionStore();
      await store.acknowledgeSafety();
      await store.markStepComplete(Routes.createAccount);
      await store.markStepComplete(Routes.preferences);
      await store.cacheProfile(const CachedProfile(
        contactName: 'Mum',
        contactNumber: '+639170000000',
        guardianCount: 2,
        consent: {'location': true},
      ));

      await store.forgetAccount();

      expect(await store.completedSteps(), isEmpty);
      expect(await store.safetyAcknowledged(), isFalse);
      final profile = await store.cachedProfile();
      expect(profile.contactName, isNull,
          reason: 'the next person on this phone must not inherit a stranger '
              'as their emergency contact');
      expect(profile.contactNumber, isNull);
      expect(profile.guardianCount, 0);
      expect(profile.consent, isEmpty);
    });

    test('it leaves anything else on the device alone', () async {
      // Three keys removed by name rather than a clear(), which would take
      // whatever else the app has stored under its own.
      SharedPreferences.setMockInitialValues({'flutter.something_else': 'kept'});
      final store = PrefsSessionStore();
      await store.markStepComplete(Routes.createAccount);

      await store.forgetAccount();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('something_else'), 'kept');
    });

    test('the in-memory store forgets the same things', () async {
      final store = InMemorySessionStore(
        acknowledged: true,
        steps: {Routes.createAccount},
        profile: const CachedProfile(contactName: 'Mum'),
      );

      await store.forgetAccount();

      expect(await store.completedSteps(), isEmpty);
      expect(await store.safetyAcknowledged(), isFalse);
      expect((await store.cachedProfile()).contactName, isNull);
    });

    testWidgets('and the app opens as it would on a phone out of the box',
        (tester) async {
      final store = InMemorySessionStore(
        acknowledged: true,
        steps: Routes.onboardingFlow.toSet(),
      );
      final session = AppSession(store: store);
      await session.load();
      expect(session.state.setupComplete, isTrue);

      // What AppSession.signOut does to the device. Firebase is not up in a
      // test, so the sign-out itself is the one line not exercised here.
      await store.forgetAccount();
      await session.load();

      await tester.pumpWidget(MaterialApp.router(
        theme: buildAppTheme(),
        routerConfig: createRouter(session),
      ));
      await tester.pumpAndSettle();

      expect(session.state.setupComplete, isFalse);
      expect(find.text(kSafetyNotice.headline), findsOneWidget,
          reason: 'a new person on this phone hears what it cannot do');
    });
  });

  group('the confirmation in front of signing out', () {
    testWidgets('asks before it does anything', (tester) async {
      var signedOut = false;
      var stayed = false;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: SignOutScreen(
          onSignOut: () => signedOut = true,
          onCancel: () => stayed = true,
        ),
      ));
      await tester.pump();

      expect(find.text('Sign out?'), findsOneWidget);
      expect(signedOut, isFalse);

      await tester.tap(find.text('Stay signed in'));
      await tester.pump();
      expect(stayed, isTrue);
      expect(signedOut, isFalse);
    });

    testWidgets('says what it costs, because it costs a blind user a lot',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: SignOutScreen(onSignOut: () {}, onCancel: () {}),
      ));
      await tester.pump();

      expect(
        find.textContaining('type your email address'),
        findsOneWidget,
        reason: 'the way back in is a form typed without seeing it',
      );
    });
  });
}
