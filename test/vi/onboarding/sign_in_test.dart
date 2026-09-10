import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/session_store.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/vi/onboarding/sign_in_screen.dart';
import 'package:impairgency/vi/widgets/vi_button.dart';

class RecordingSpeaker implements Speaker {
  final List<String> said = [];

  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;

  @override
  Future<void> repeat() async {
    if (lastSpoken != null) said.add(lastSpoken!);
  }

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);

  @override
  Future<void> stop() async {}
}

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: child));
  await tester.pump();
}

Future<void> fillIn(WidgetTester tester, String email, String password) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);
  await tester.pump();
}

/// The button carrying [label], not the heading that happens to share its
/// words: this screen's title is "Sign in" and so is its primary action.
Finder action(String label) =>
    find.descendant(of: find.byType(ViButton), matching: find.text(label));

Future<void> tapAction(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  group('the screen the Sign in button never had', () {
    testWidgets('hands the typed email and password over, trimmed',
        (tester) async {
      String? email;
      String? password;
      await pump(
        tester,
        SignInScreen(
          onSignIn: (e, p) async {
            email = e;
            password = p;
            return null;
          },
          onCreateAccount: () {},
        ),
      );

      await fillIn(tester, '  someone@example.com ', 'a real password');
      await tapAction(tester, action('Sign in'));

      expect(email, 'someone@example.com',
          reason: 'a phone keyboard adds a space after a word');
      expect(password, 'a real password');
    });

    testWidgets('a password shorter than eight characters is still tried',
        (tester) async {
      // Create-account requires eight. Applying that rule to a password being
      // typed *back* refuses a working password on the client, and blames the
      // user for a rule that was made after their account was.
      var tried = false;
      await pump(
        tester,
        SignInScreen(
          onSignIn: (_, __) async {
            tried = true;
            return null;
          },
          onCreateAccount: () {},
        ),
      );

      await fillIn(tester, 'someone@example.com', 'short');
      await tapAction(tester, action('Sign in'));

      expect(tried, isTrue);
    });

    testWidgets('an address that is not one is said, not sent', (tester) async {
      final speaker = RecordingSpeaker();
      var tried = false;
      await pump(
        tester,
        SignInScreen(
          speaker: speaker,
          onSignIn: (_, __) async {
            tried = true;
            return null;
          },
          onCreateAccount: () {},
        ),
      );

      await fillIn(tester, 'someone', 'a real password');
      await tapAction(tester, action('Sign in'));

      expect(tried, isFalse);
      expect(speaker.said, contains('That does not look like an email address.'));
      expect(find.text('That does not look like an email address.'),
          findsOneWidget);
    });

    testWidgets('an empty password is said, not sent', (tester) async {
      final speaker = RecordingSpeaker();
      var tried = false;
      await pump(
        tester,
        SignInScreen(
          speaker: speaker,
          onSignIn: (_, __) async {
            tried = true;
            return null;
          },
          onCreateAccount: () {},
        ),
      );

      await fillIn(tester, 'someone@example.com', '');
      await tapAction(tester, action('Sign in'));

      expect(tried, isFalse);
      expect(speaker.said, contains('Type your password.'));
    });

    testWidgets('a refusal from Firebase is spoken as well as shown',
        (tester) async {
      // An error a blind user cannot hear is not an error message.
      final speaker = RecordingSpeaker();
      await pump(
        tester,
        SignInScreen(
          speaker: speaker,
          onSignIn: (_, __) async =>
              'That email and password do not match an account.',
          onCreateAccount: () {},
        ),
      );

      await fillIn(tester, 'someone@example.com', 'wrong password');
      await tapAction(tester, action('Sign in'));
      await tester.pump();

      expect(speaker.said,
          contains('That email and password do not match an account.'));
      expect(find.text('That email and password do not match an account.'),
          findsOneWidget);
    });

    testWidgets('offers the other door, so this one is not a dead end too',
        (tester) async {
      var asked = false;
      await pump(
        tester,
        SignInScreen(
          onSignIn: (_, __) async => null,
          onCreateAccount: () => asked = true,
        ),
      );

      await tapAction(tester, action('Create an account instead'));
      expect(asked, isTrue);
    });

    testWidgets('every control is big enough to find by sweeping',
        (tester) async {
      await pump(
        tester,
        SignInScreen(onSignIn: (_, __) async => null, onCreateAccount: () {}),
      );

      for (final element in find.byType(ViButton).evaluate()) {
        expect(tester.getSize(find.byWidget(element.widget)).height,
            greaterThanOrEqualTo(ViButton.minHeight));
      }
    });
  });

  group('the loop the welcome screen used to send people round', () {
    testWidgets('Sign in opens sign-in, not Create your account',
        (tester) async {
      // The bug: both buttons on the welcome screen went to
      // /onboarding/account. A returning user typed the email they already
      // had and was told there was already an account with it and to try
      // signing in instead — which is what they had just done.
      final session = AppSession(
        store: InMemorySessionStore(acknowledged: true),
      );
      await session.load();
      await tester.pumpWidget(MaterialApp.router(
        theme: buildAppTheme(),
        routerConfig: createRouter(session),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to ImpairGency'), findsOneWidget);
      await tapAction(tester, action('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('Create your account'), findsNothing);
      expect(find.textContaining('Step 1 of'), findsNothing,
          reason: 'signing in is not step one of setting up');
    });

    testWidgets('and from there, the way on to creating one', (tester) async {
      final session = AppSession(
        store: InMemorySessionStore(acknowledged: true),
      );
      await session.load();
      final router = createRouter(session);
      await tester.pumpWidget(
          MaterialApp.router(theme: buildAppTheme(), routerConfig: router));
      await tester.pumpAndSettle();

      router.go(Routes.signIn);
      await tester.pumpAndSettle();
      await tapAction(tester, action('Create an account instead'));
      await tester.pumpAndSettle();

      // Via the question the tester asked for: which app is this for?
      expect(find.text('Who is this account for?'), findsOneWidget);
      await tapAction(tester, action('Visually impaired user'));
      await tester.pumpAndSettle();

      expect(find.text('Create your account'), findsOneWidget);
      expect(session.state.isGuardian, isFalse);
    });

    testWidgets('and the guardian door leads to the guardian form',
        (tester) async {
      final session = AppSession(
        store: InMemorySessionStore(acknowledged: true),
      );
      await session.load();
      final router = createRouter(session);
      await tester.pumpWidget(
          MaterialApp.router(theme: buildAppTheme(), routerConfig: router));
      await tester.pumpAndSettle();

      router.go(Routes.chooseRole);
      await tester.pumpAndSettle();
      await tapAction(tester, action('Guardian'));
      await tester.pumpAndSettle();

      expect(find.text('Create a guardian account'), findsOneWidget);
    });
  });
}
