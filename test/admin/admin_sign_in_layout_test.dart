import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/admin_shell.dart';
import 'package:impairgency/admin/screens/admin_sign_in_screen.dart';

/// The front door, at the widths it is actually opened at.
///
/// The page splits at [kAdminSidebarBreakpoint] — the same width where the
/// dashboard behind it swaps its sidebar for a drawer — and everything on it
/// has to survive both sides of that line, a short window, and a phone.

const phone = Size(390, 844);
const short = Size(1280, 560);
const laptop = Size(1280, 800);
const wide = Size(1920, 1080);

Future<void> pump(
  WidgetTester tester,
  Widget screen, {
  Size size = laptop,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAdminTheme(), home: screen));
  await tester.pumpAndSettle();
}

Widget form({SignInHandler? onSignIn}) =>
    AdminSignInScreen(onSignIn: onSignIn ?? (_, __) async => null);

Widget notOnRoster() => AdminSignInScreen(
      onSignIn: (_, __) async => null,
      signedInAs: 'dex@example.com',
      signedInUid: 'YNNCSK6e0mRH39A8eBFOWqOYHp03',
      onSignOut: () {},
    );

void main() {
  group('every width, both states', () {
    for (final size in [phone, short, laptop, wide]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('the form lays out at $label', (tester) async {
        await pump(tester, form(), size: size);
        expect(tester.takeException(), isNull);

        // Whatever the width, the way in is on the screen.
        final button = tester.getRect(find.byType(FilledButton));
        expect(button.top, greaterThanOrEqualTo(0.0));
        expect(button.bottom, lessThanOrEqualTo(size.height));
      });

      testWidgets('the roster refusal lays out at $label', (tester) async {
        await pump(tester, notOnRoster(), size: size);
        expect(tester.takeException(), isNull);
        expect(find.text('admins/YNNCSK6e0mRH39A8eBFOWqOYHp03'),
            findsOneWidget);
      });
    }
  });

  group('the brand', () {
    testWidgets('is on the panel on a desktop', (tester) async {
      await pump(tester, form(), size: laptop);
      expect(find.text('ImpairGency admin'), findsOneWidget);

      // On the panel means on the left, beside the form rather than above it.
      final brand = tester.getRect(find.text('ImpairGency admin'));
      final card = tester.getRect(find.byType(FilledButton));
      expect(brand.right, lessThan(card.left));
    });

    testWidgets('moves into the card on a phone', (tester) async {
      // Not dropped. A phone has no room for a panel beside the form, which
      // is not a reason for the product to go unnamed on its own login page.
      await pump(tester, form(), size: phone);
      expect(find.text('ImpairGency admin'), findsOneWidget);

      final brand = tester.getRect(find.text('ImpairGency admin'));
      final card = tester.getRect(find.byType(FilledButton));
      expect(brand.bottom, lessThan(card.top));
    });

    testWidgets('names the sections the dashboard actually has',
        (tester) async {
      // From adminSections, so the panel cannot advertise a screen that is
      // not there.
      await pump(tester, form(), size: laptop);
      for (final section in adminSections) {
        expect(find.text(section.label), findsOneWidget, reason: section.label);
      }
    });
  });

  group('the form', () {
    testWidgets('shows a refusal as a banner, not as a field error',
        (tester) async {
      await pump(
        tester,
        form(
          onSignIn: (_, __) async =>
              'That email and password do not match an account.',
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'a@b.com');
      await tester.enterText(find.byType(TextField).last, 'wrong');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      final message = find.textContaining('do not match an account');
      expect(message, findsOneWidget);

      // Above the button, where the eye already is — not under a field, below
      // the fold of a short card.
      expect(tester.getRect(message).bottom,
          lessThan(tester.getRect(find.byType(FilledButton)).top));
    });

    testWidgets('clears the refusal when the next attempt starts',
        (tester) async {
      var attempts = 0;
      await pump(
        tester,
        form(onSignIn: (_, __) async => ++attempts == 1 ? 'No.' : null),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text('No.'), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text('No.'), findsNothing,
          reason: 'a stale refusal beside a fresh attempt is a lie');
    });

    testWidgets('trims the email before trying it', (tester) async {
      // Password managers and phone keyboards both add a trailing space, and
      // "no such account" is a poor way to learn that.
      String? seen;
      await pump(tester, form(onSignIn: (email, __) async {
        seen = email;
        return null;
      }));
      await tester.enterText(find.byType(TextField).first, '  dex@a.com ');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(seen, 'dex@a.com');
    });

    testWidgets('does not trim the password', (tester) async {
      // A space is a character. Trimming one out of a password turns a
      // correct password into a wrong one.
      String? seen;
      await pump(tester, form(onSignIn: (_, password) async {
        seen = password;
        return null;
      }));
      await tester.enterText(find.byType(TextField).last, ' hunter2 ');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(seen, ' hunter2 ');
    });

    testWidgets('hides the password until asked, and says which it is doing',
        (tester) async {
      await pump(tester, form());
      final password = tester.widget<TextField>(find.byType(TextField).last);
      expect(password.obscureText, isTrue);

      expect(find.byTooltip('Show password'), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField).last).obscureText,
          isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('says what it is doing while it does it', (tester) async {
      final gate = Completer<String?>();
      await pump(tester, form(onSignIn: (_, __) => gate.future));

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Signing in…'), findsOneWidget,
          reason: 'a spinner says something is happening; the word says what');
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull, reason: 'a second submit while the first is in flight');

      gate.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Signing in…'), findsNothing);
    });
  });
}
