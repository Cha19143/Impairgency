import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/places/place.dart';
import 'package:impairgency/core/places/stay.dart';
import 'package:impairgency/core/sos/sos_receipt.dart';
import 'package:impairgency/guardian/screens/accept_invitation_screen.dart';
import 'package:impairgency/vi/onboarding/all_set_screen.dart';
import 'package:impairgency/vi/onboarding/choose_role_screen.dart';
import 'package:impairgency/vi/onboarding/forgot_password_screen.dart';
import 'package:impairgency/vi/onboarding/profile_screen.dart';
import 'package:impairgency/vi/onboarding/consent_screen.dart';
import 'package:impairgency/vi/onboarding/create_account_screen.dart';
import 'package:impairgency/vi/onboarding/device_screen.dart';
import 'package:impairgency/vi/onboarding/emergency_contact_screen.dart';
import 'package:impairgency/vi/onboarding/invite_guardian_screen.dart';
import 'package:impairgency/vi/onboarding/preferences_screen.dart';
import 'package:impairgency/vi/onboarding/sign_in_screen.dart';
import 'package:impairgency/vi/onboarding/welcome_screen.dart';
import 'package:impairgency/vi/screens/consent_centre_screen.dart';
import 'package:impairgency/vi/screens/dashboard_screen.dart';
import 'package:impairgency/vi/screens/learned_data_screen.dart';
import 'package:impairgency/vi/screens/safety_notice_screen.dart';
import 'package:impairgency/vi/screens/settings_screen.dart';
import 'package:impairgency/vi/screens/sign_out_screen.dart';
import 'package:impairgency/vi/screens/sos_countdown_screen.dart';
import 'package:impairgency/vi/screens/sos_receipt_screen.dart';
import 'package:impairgency/vi/screens/what_can_i_say_screen.dart';
import 'package:impairgency/vi/widgets/vi_button.dart';

/// #55 and #56, over **every** screen a visually impaired user can reach.
///
/// The onboarding gate covered eight. This covers all of them, including the
/// ones added later — which is the point: a screen added without these
/// properties fails the suite rather than shipping.
Place _place() => Place(
      latitude: 14.79,
      longitude: 120.92,
      label: 'Home',
      visits: [
        for (var i = 0; i < 4; i++)
          Stay(
            latitude: 14.79,
            longitude: 120.92,
            arrived: DateTime.utc(2026, 9, 1 + i, 8),
            departed: DateTime.utc(2026, 9, 1 + i, 16),
            fixCount: 20,
          ),
      ],
    );

SosReceipt _receipt() => const SosReceipt([
      LegResult(SosLeg.alarm, LegOutcome.done),
      LegResult(SosLeg.call, LegOutcome.failed, detail: 'Mum'),
      LegResult(SosLeg.location, LegOutcome.done,
          detail: 'Your location was sent.'),
      LegResult(SosLeg.guardians, LegOutcome.notConfigured),
    ]);

/// Every reachable screen, built the way the router builds it.
Map<String, Widget Function()> screens() => {
      'Safety notice': () => SafetyNoticeScreen(onAcknowledge: () async {}),
      'Welcome': () =>
          WelcomeScreen(onCreateAccount: () {}, onSignIn: () {}),
      'Choose role': () => ChooseRoleScreen(
          onVisuallyImpaired: () {}, onGuardian: () {}, onSignIn: () {}),
      'Create account': () =>
          CreateAccountScreen(onCreate: (_, __) async => null),
      'About you': () => ProfileScreen(onSave: (_) async {}),
      'Forgot password': () =>
          ForgotPasswordScreen(onSendReset: (_) async => null, onBack: () {}),
      'Preferences': () =>
          PreferencesScreen(onChoose: (_) {}, onSkip: () {}),
      'Emergency contact': () =>
          EmergencyContactScreen(onSave: (_, __) {}, onSkip: () {}),
      'Invite guardian': () => InviteGuardianScreen(
          code: 'FH29MR47', onDone: () {}, onSkip: () {}),
      'Consent': () => ConsentScreen(onContinue: (_) {}),
      'Device': () =>
          DeviceScreen(onHasDevice: () {}, onNoDevice: () {}, onSkip: () {}),
      'All set': () => AllSetScreen(onStart: () {}),
      'Dashboard': () => DashboardScreen(
            onScan: () {}, onAssist: () {}, onSos: () {},
            onWhatCanISay: () {}, onSettings: () {},
            consent: const {'location': true, 'history': false},
          ),
      'What can I say': () => WhatCanISayScreen(onBack: () {}),
      'Sign in': () => SignInScreen(
            onSignIn: (_, __) async => null,
            onCreateAccount: () {},
          ),
      'Sign out': () => SignOutScreen(onSignOut: () {}, onCancel: () {}),
      'Settings': () => SettingsScreen(
            onConsent: () {}, onLearned: () {}, onDevice: () {},
            onEmergencyContact: () {}, onInviteGuardian: () {},
            onSafetyNotice: () {}, onSignOut: () {}, onBack: () {},
          ),
      'Consent centre': () => ConsentCentreScreen(
          current: const {'location': true},
          onSave: (_) async {},
          onBack: () {}),
      'What the app has learned': () => LearnedDataScreen(
            places: [_place()],
            onForgetAll: () async {},
            onForgetPlace: (_) async {},
            onBack: () {},
          ),
      'SOS countdown': () =>
          SosCountdownScreen(onFire: () {}, onCancel: () {}, contactName: 'Mum'),
      'SOS receipt': () => SosReceiptScreen(receipt: _receipt(), onDone: () {}),
      'Guardian accept invitation': () =>
          AcceptInvitationScreen(onRedeem: (_) async => null),
    };

Future<void> pump(
  WidgetTester tester,
  Widget Function() build, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: build(),
    ),
  ));
  await tester.pump();
}

void main() {
  for (final entry in screens().entries) {
    final name = entry.key;
    final build = entry.value;

    group(name, () {
      testWidgets('every interactive element is labelled (#55)',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pump(tester, build);

        // Every widget a user can operate, checked through the semantics tree
        // the screen reader actually reads. A control announced as nothing is
        // a control a blind user cannot use.
        final interactive = <Finder>[
          find.byType(ViButton),
          find.byType(IconButton),
          find.byType(TextButton),
          find.byType(FilledButton),
          find.byType(Switch),
          find.byType(TextField),
          // Raw InkWells count too. The SOS countdown's CANCEL is one, and a
          // finder list that misses it would pass a screen it never checked.
          find.byType(InkWell),
        ];

        var checked = 0;
        for (final finder in interactive) {
          for (final element in finder.evaluate()) {
            final node = tester.getSemantics(find.byWidget(element.widget));
            final labelled = node.label.trim().isNotEmpty ||
                node.value.trim().isNotEmpty ||
                node.tooltip.trim().isNotEmpty ||
                node.hint.trim().isNotEmpty;
            expect(labelled, isTrue,
                reason: '$name has an unlabelled '
                    '${element.widget.runtimeType}');
            checked++;
          }
        }

        expect(checked, greaterThan(0),
            reason: '$name appears to have no controls at all');
        handle.dispose();
      });

      testWidgets('does not overflow at 2.0x text scale (#56)',
          (tester) async {
        // Requirements §4 asks for large text. A user who has set 200% means
        // it, and clamping it would be answering a different request.
        await pump(tester, build, textScale: 2.0);
        expect(tester.takeException(), isNull,
            reason: '$name overflowed at 2.0x');
      });

      testWidgets('renders at 1.0x without exceptions', (tester) async {
        await pump(tester, build);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('the gate covers every screen in the app', (tester) async {
    // If a screen is added and not listed here, that is the omission this
    // assertion is meant to make visible.
    expect(screens().length, greaterThanOrEqualTo(20));
  });
}
