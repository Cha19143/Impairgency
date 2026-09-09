import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/profile/impairment.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/vi/onboarding/choose_role_screen.dart';
import 'package:impairgency/vi/onboarding/forgot_password_screen.dart';
import 'package:impairgency/vi/onboarding/profile_screen.dart';
import 'package:impairgency/vi/onboarding/sign_in_screen.dart';

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

Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

/// The list sits below the fold in the test window; a real thumb scrolls.
Future<void> tapRow(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  group('who is this account for', () {
    testWidgets('two doors, and each goes where it says', (tester) async {
      var vi = 0;
      var guardian = 0;
      await tester.pumpWidget(host(ChooseRoleScreen(
        onVisuallyImpaired: () => vi++,
        onGuardian: () => guardian++,
        onSignIn: () {},
      )));
      await tester.tap(find.text('Visually impaired user'));
      await tester.tap(find.text('Guardian'));
      expect(vi, 1);
      expect(guardian, 1);
    });

    testWidgets('says both choices before either is touched', (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(ChooseRoleScreen(
        speaker: speaker,
        onVisuallyImpaired: () {},
        onGuardian: () {},
        onSignIn: () {},
      )));
      await tester.pump();
      final said = speaker.said.join(' ');
      expect(said, contains('Visually impaired user'));
      expect(said, contains('guardian'));
    });
  });

  group('about you', () {
    testWidgets('the impairment is a list, and Other opens a field',
        (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(ProfileScreen(
        speaker: speaker,
        onSave: (_) async {},
      )));
      await tester.pump();

      for (final choice in kImpairmentChoices.values) {
        expect(find.text(choice.label), findsOneWidget);
      }
      expect(find.text('Describe it in your own words'), findsNothing);

      await tapRow(tester, 'Other');
      await tester.pumpAndSettle();

      expect(find.text('Describe it in your own words'), findsOneWidget);
      expect(speaker.said.last, contains('Other'));
    });

    testWidgets('a choice is announced when made', (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(ProfileScreen(
        speaker: speaker,
        onSave: (_) async {},
      )));
      await tapRow(tester, 'Low vision');
      expect(speaker.said.last, 'Low vision, chosen.');
    });

    testWidgets('hands over what was typed and chosen', (tester) async {
      PersonalInfo? saved;
      await tester.pumpWidget(host(ProfileScreen(
        onSave: (info) async => saved = info,
      )));
      await tester.enterText(find.byType(TextField).at(0), 'Ana');
      await tester.enterText(find.byType(TextField).at(1), '34');
      await tapRow(tester, 'Blind');
      await tester.ensureVisible(find.byType(TextField).at(2));
      await tester.enterText(find.byType(TextField).at(2), '0917 000 0000');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.name, 'Ana');
      expect(saved!.age, 34);
      expect(saved!.impairment, ImpairmentType.blind);
      expect(saved!.phone, '09170000000');
    });

    testWidgets('a missing answer is said, not only shown', (tester) async {
      final speaker = RecordingSpeaker();
      var saves = 0;
      await tester.pumpWidget(host(ProfileScreen(
        speaker: speaker,
        onSave: (_) async => saves++,
      )));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(saves, 0);
      expect(find.text('Enter your name.'), findsOneWidget);
      expect(speaker.said.last, 'Enter your name.');
    });

    testWidgets('selection is not conveyed by colour alone', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(ProfileScreen(onSave: (_) async {})));
      await tapRow(tester, 'Blind');

      final node = tester.getSemantics(find.text('Blind'));
      expect(node.flagsCollection.isSelected.toString(), contains('isTrue'));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      handle.dispose();
    });
  });

  group('forgot password', () {
    testWidgets('the sign-in screen offers it, with the email typed so far',
        (tester) async {
      String? carried;
      await tester.pumpWidget(host(SignInScreen(
        onSignIn: (_, __) async => null,
        onCreateAccount: () {},
        onForgotPassword: (email) => carried = email,
      )));
      await tester.enterText(find.byType(TextField).first, 'ana@example.com');
      await tester.tap(find.text('Forgot your password?'));
      expect(carried, 'ana@example.com');
    });

    testWidgets('sends the link and says so out loud', (tester) async {
      final speaker = RecordingSpeaker();
      String? sentTo;
      await tester.pumpWidget(host(ForgotPasswordScreen(
        speaker: speaker,
        initialEmail: 'ana@example.com',
        onSendReset: (email) async {
          sentTo = email;
          return null;
        },
        onBack: () {},
      )));
      await tester.tap(find.text('Send me the link'));
      await tester.pumpAndSettle();

      expect(sentTo, 'ana@example.com');
      expect(speaker.said.last,
          ForgotPasswordScreen.sentMessage('ana@example.com'));
      expect(find.text('Back to sign in'), findsOneWidget);
      expect(find.text('Send me the link'), findsNothing,
          reason: 'one link is enough');
    });

    testWidgets('never says whether the address has an account',
        (tester) async {
      expect(ForgotPasswordScreen.sentMessage('x@y.z'), startsWith('If there is'));
    });

    testWidgets('a refusal is spoken as well as shown', (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(ForgotPasswordScreen(
        speaker: speaker,
        onSendReset: (_) async => 'No connection. Check your network and try again.',
        onBack: () {},
      )));
      await tester.enterText(find.byType(TextField), 'ana@example.com');
      await tester.tap(find.text('Send me the link'));
      await tester.pumpAndSettle();
      expect(find.text('No connection. Check your network and try again.'),
          findsOneWidget);
      expect(speaker.said.last, contains('No connection'));
    });

    testWidgets('an address that is not one is not sent', (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(ForgotPasswordScreen(
        onSendReset: (_) async {
          calls++;
          return null;
        },
        onBack: () {},
      )));
      await tester.enterText(find.byType(TextField), 'ana');
      await tester.tap(find.text('Send me the link'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  });
}
