import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/vi/onboarding/all_set_screen.dart';
import 'package:impairgency/vi/onboarding/consent_screen.dart';
import 'package:impairgency/vi/onboarding/create_account_screen.dart';
import 'package:impairgency/vi/onboarding/device_screen.dart';
import 'package:impairgency/vi/onboarding/emergency_contact_screen.dart';
import 'package:impairgency/vi/onboarding/invite_guardian_screen.dart';
import 'package:impairgency/vi/onboarding/preferences_screen.dart';
import 'package:impairgency/vi/onboarding/welcome_screen.dart';
import 'package:impairgency/vi/widgets/vi_button.dart';

class RecordingSpeaker implements Speaker {
  final List<String> said = [];

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);

  @override
  Future<void> stop() async {}
}

/// Every screen in the flow, built the way the router builds it.
List<(String, Widget Function(Speaker))> screens() => [
      ('Welcome', (s) => WelcomeScreen(
            speaker: s,
            onCreateAccount: () {},
            onSignIn: () {},
          )),
      ('Create account', (s) => CreateAccountScreen(
            speaker: s,
            onCreate: (_, __) async => null,
          )),
      ("How you'll use it", (s) => PreferencesScreen(
            speaker: s,
            onChoose: (_) {},
            onSkip: () {},
          )),
      ('Emergency contact', (s) => EmergencyContactScreen(
            speaker: s,
            onSave: (_, __) {},
            onSkip: () {},
          )),
      ('Invite a guardian', (s) => InviteGuardianScreen(
            speaker: s,
            code: 'FH29MR47',
            onDone: () {},
            onSkip: () {},
          )),
      ('Consent', (s) => ConsentScreen(speaker: s, onContinue: (_) {})),
      ('Device', (s) => DeviceScreen(
            speaker: s,
            onHasDevice: () {},
            onNoDevice: () {},
            onSkip: () {},
          )),
      ('All set', (s) => AllSetScreen(speaker: s, onStart: () {})),
    ];

Future<RecordingSpeaker> pump(
  WidgetTester tester,
  Widget Function(Speaker) build, {
  double textScale = 1.0,
  Size size = const Size(390, 844),
}) async {
  final speaker = RecordingSpeaker();
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: build(speaker),
    ),
  ));
  await tester.pump();
  return speaker;
}

void main() {
  group('every onboarding screen', () {
    for (final (name, build) in screens()) {
      testWidgets('$name speaks itself on arrival', (tester) async {
        // A user who cannot see the screen has to be told what is on it,
        // including what the choices are.
        final speaker = await pump(tester, build);
        expect(speaker.said, isNotEmpty, reason: name);
        expect(speaker.said.first, isNotEmpty, reason: '$name spoke a blank');
      });

      testWidgets('$name labels every control', (tester) async {
        final handle = tester.ensureSemantics();
        await pump(tester, build);

        final buttons = find.byType(ViButton);
        expect(buttons, findsWidgets, reason: '$name has no actions');
        for (final element in buttons.evaluate()) {
          final button = element.widget as ViButton;
          final label = button.semanticLabel ?? button.label;
          expect(label.trim(), isNotEmpty,
              reason: '$name has an unlabelled button');
        }
        handle.dispose();
      });

      testWidgets('$name keeps its actions on screen at 2.0x text',
          (tester) async {
        // The text may scroll. The controls may not: someone who cannot see the
        // screen should not have to discover the button is below the fold.
        await pump(tester, build, textScale: 2.0);
        expect(tester.takeException(), isNull, reason: '$name overflowed');

        final buttons = find.byType(ViButton);
        final screenHeight = tester.view.physicalSize.height /
            tester.view.devicePixelRatio;
        for (final element in buttons.evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.top, lessThan(screenHeight),
              reason: '$name pushed a control off screen');
        }
      });

      testWidgets('$name has touch targets a sweeping finger can find',
          (tester) async {
        await pump(tester, build);
        for (final element in find.byType(ViButton).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.height, greaterThanOrEqualTo(56),
              reason: '$name has a control smaller than a fingertip');
        }
      });
    }
  });

  group('the flow does what the rework promised', () {
    testWidgets('Create account never offers to dictate credentials',
        (tester) async {
      // ui.pdf p.7 offered to "speak the details instead of typing". A password
      // said out loud is not a password.
      final speaker = await pump(
        tester,
        (s) => CreateAccountScreen(speaker: s, onCreate: (_, __) async => null),
      );
      final spoken = speaker.said.join(' ').toLowerCase();

      expect(spoken, contains('keyboard'));
      expect(spoken, contains('not a password'));
      expect(spoken, isNot(contains('speak your password')));
      expect(spoken, isNot(contains('say your email')));
    });

    testWidgets('Consent starts with everything off', (tester) async {
      await pump(tester, (s) => ConsentScreen(speaker: s, onContinue: (_) {}));
      for (final element in find.byType(Switch).evaluate()) {
        expect((element.widget as Switch).value, isFalse,
            reason: 'consent that is on by default is not consent');
      }
    });

    testWidgets('Consent hands back every choice, all false by default',
        (tester) async {
      Map<String, bool>? given;
      await pump(tester,
          (s) => ConsentScreen(speaker: s, onContinue: (v) => given = v));
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(given, isNotNull);
      expect(given!.length, kConsentChoices.length);
      expect(given!.values.every((v) => v == false), isTrue);
    });

    testWidgets('every consent line says who can see the result',
        (tester) async {
      // "Share location" without "your guardian sees where you are" is not
      // informed consent.
      for (final choice in kConsentChoices) {
        expect(choice.detail.trim(), isNotEmpty, reason: choice.key);
        expect(choice.detail.length, greaterThan(30), reason: choice.key);
      }
    });

    testWidgets('skipping the emergency contact warns before it happens',
        (tester) async {
      var skipped = false;
      final speaker = await pump(
        tester,
        (s) => EmergencyContactScreen(
          speaker: s,
          onSave: (_, __) {},
          onSkip: () => skipped = true,
        ),
      );

      await tester.tap(find.text('Skip for now'));
      await tester.pump();

      expect(skipped, isFalse, reason: 'the first tap explains, it does not do');
      expect(speaker.said.join(' '), contains('nobody to call'));
      expect(find.text('Skip anyway'), findsOneWidget);

      await tester.tap(find.text('Skip anyway'));
      await tester.pump();
      expect(skipped, isTrue);
    });

    testWidgets('All set offers exactly one action', (tester) async {
      // cprwire offered "GO TO DASHBOARD" and "GO TO LOGIN" - sending a user
      // who had just registered back to a sign-in screen.
      await pump(tester, (s) => AllSetScreen(speaker: s, onStart: () {}));
      expect(find.byType(ViButton), findsOneWidget);
      expect(find.textContaining('Login'), findsNothing);
      expect(find.textContaining('Sign in'), findsNothing);
    });

    testWidgets('All set says what is missing rather than congratulating',
        (tester) async {
      final speaker = await pump(
        tester,
        (s) => AllSetScreen(
          speaker: s,
          onStart: () {},
          hasEmergencyContact: false,
          hasGuardian: false,
        ),
      );
      expect(speaker.said.join(' '), contains('nobody to call'));
    });

    testWidgets('the guardian code is spelled out, not read as a word',
        (tester) async {
      final speaker = await pump(
        tester,
        (s) => InviteGuardianScreen(
          speaker: s,
          code: 'FH29MR47',
          onDone: () {},
          onSkip: () {},
        ),
      );
      final spoken = speaker.said.join(' ');

      expect(spoken, contains('F, H, 2, 9'));
      expect(spoken, contains('M, R, 4, 7'));
      expect(spoken, isNot(contains('FH29MR47')),
          reason: 'reading it as a word is useless to whoever writes it down');
    });

    testWidgets('Device gates nothing and can be skipped', (tester) async {
      var skipped = false;
      await pump(
        tester,
        (s) => DeviceScreen(
          speaker: s,
          onHasDevice: () {},
          onNoDevice: () {},
          onSkip: () => skipped = true,
        ),
      );
      await tester.tap(find.text('Skip — ask me later'));
      await tester.pump();
      expect(skipped, isTrue);
    });

    testWidgets('the vision question is gone', (tester) async {
      // Replaced by a question that changes behaviour.
      final speaker = await pump(
        tester,
        (s) => PreferencesScreen(speaker: s, onChoose: (_) {}, onSkip: () {}),
      );
      final spoken = speaker.said.join(' ').toLowerCase();
      expect(spoken, isNot(contains('vision loss')));
      expect(spoken, isNot(contains('blind')));
      expect(spoken, contains('screen'));
    });
  });
}
