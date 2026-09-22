import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/admin_sign_in_screen.dart';

Future<void> pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAdminTheme(), home: screen));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers the form when nobody is signed in', (tester) async {
    await pump(tester, AdminSignInScreen(onSignIn: (_, __) async => null));
    expect(find.text('ImpairGency admin'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('shows the reason a sign-in was refused', (tester) async {
    await pump(
      tester,
      AdminSignInScreen(
        onSignIn: (_, __) async => 'That email and password do not match an '
            'account.',
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'a@b.com');
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('do not match an account'), findsOneWidget);
  });

  group('signed in, but not on the roster', () {
    // The failure that looked like "login does not work": authentication
    // succeeded, the guard sent the visitor back to the sign-in screen they
    // were already on, and nothing appeared to happen.
    Widget screen({VoidCallback? onSignOut}) => AdminSignInScreen(
          onSignIn: (_, __) async => null,
          signedInAs: 'dex@example.com',
          signedInUid: 'YNNCSK6e0mRH39A8eBFOWqOYHp03',
          onSignOut: onSignOut,
        );

    testWidgets('says so, instead of showing the form again', (tester) async {
      await pump(tester, screen());

      expect(find.text('Signed in, but not an administrator'), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: 'offering the form again is what caused the confusion');
    });

    testWidgets('names the account that is signed in', (tester) async {
      await pump(tester, screen());
      expect(find.textContaining('dex@example.com'), findsOneWidget);
    });

    testWidgets('gives the exact document to create, selectable to copy',
        (tester) async {
      await pump(tester, screen());
      final path = find.text('admins/YNNCSK6e0mRH39A8eBFOWqOYHp03');
      expect(path, findsOneWidget);
      expect(
        tester.widget(find.ancestor(
          of: path,
          matching: find.byType(SelectableText),
        )),
        isNotNull,
        reason: 'a UID nobody can copy is a UID nobody can act on',
      );
    });

    testWidgets('explains why it cannot be granted from here', (tester) async {
      await pump(tester, screen());
      expect(find.textContaining('deny-all from every client'), findsOneWidget);
      expect(find.textContaining('without a paid plan'), findsOneWidget);
    });

    testWidgets('offers a way out', (tester) async {
      var signedOut = false;
      await pump(tester, screen(onSignOut: () => signedOut = true));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
    });

    testWidgets('the heading is announced as a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, screen());
      expect(find.bySemanticsLabel('Signed in, but not an administrator'),
          findsOneWidget);
      handle.dispose();
    });
  });

  group('signed in, but the roster did not answer', () {
    // An administrator on a cold connection used to be told they were not
    // one, and the dashboard stayed shut for the rest of the session.
    testWidgets('says the check is still going, not that they are refused',
        (tester) async {
      await pump(
        tester,
        AdminSignInScreen(
          onSignIn: (_, __) async => null,
          signedInAs: 'dex@example.com',
          signedInUid: 'uid-1',
          checkingRoster: true,
          onCheckAgain: () async {},
          onSignOut: () {},
        ),
      );

      expect(find.text('Checking the admin roster…'), findsOneWidget);
      expect(find.text('Signed in, but not an administrator'), findsNothing);
      expect(find.textContaining('dex@example.com'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Check again asks, and says it is asking', (tester) async {
      final answer = Completer<void>();
      var asked = 0;
      await pump(
        tester,
        AdminSignInScreen(
          onSignIn: (_, __) async => null,
          signedInAs: 'dex@example.com',
          checkingRoster: true,
          onCheckAgain: () {
            asked++;
            return answer.future;
          },
        ),
      );

      await tester.tap(find.text('Check again'));
      await tester.pump();
      expect(asked, 1);
      expect(find.text('Checking…'), findsOneWidget);

      await tester.tap(find.text('Checking…'));
      await tester.pump();
      expect(asked, 1, reason: 'one question at a time');

      answer.complete();
      await tester.pumpAndSettle();
      expect(find.text('Check again'), findsOneWidget);
    });
  });
}
