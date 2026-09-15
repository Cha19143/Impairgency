import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/pairing/pairing_code.dart';
import 'package:impairgency/guardian/screens/accept_invitation_screen.dart';

Widget host(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: child);

void main() {
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  testWidgets('redeems the code the user typed, normalised', (tester) async {
    String? seen;
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (code) async {
        seen = code;
        return null;
      },
    )));

    await type(tester, 'fh29 mr47');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(seen, 'FH29MR47');
  });

  testWidgets('uppercases as you type, so it matches what you heard',
      (tester) async {
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (_) async => null,
    )));

    await type(tester, 'fh29mr47');
    expect(find.text('FH29MR47'), findsOneWidget);
  });

  testWidgets('refuses to accept characters that are not in the alphabet',
      (tester) async {
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (_) async => null,
    )));

    // Typing an O and being told later it was invalid is worse than the key
    // simply doing nothing.
    await type(tester, 'FHO0BDE1');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'FH');
  });

  testWidgets('calls back on success', (tester) async {
    var accepted = false;
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (_) async => null,
      onAccepted: () => accepted = true,
    )));

    await type(tester, 'FH29MR47');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
  });

  testWidgets('shows the reason a code was refused, not a generic error',
      (tester) async {
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (_) async =>
          pairingRejectionMessage(PairingCodeRejection.expired),
    )));

    await type(tester, 'FH29MR47');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('expired'), findsOneWidget);
    expect(find.textContaining('thirty minutes'), findsWidgets);
  });

  testWidgets('does not call the server for a code that cannot be valid',
      (tester) async {
    var called = false;
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (_) async {
        called = true;
        return null;
      },
    )));

    await type(tester, 'FH29');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.textContaining('eight characters'), findsOneWidget);
  });

  testWidgets('clears the error as soon as they start correcting it',
      (tester) async {
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (_) async =>
          pairingRejectionMessage(PairingCodeRejection.notFound),
    )));

    await type(tester, 'FH29MR47');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not find'), findsOneWidget);

    await type(tester, 'FH29MR44');
    // A stale failure sitting under a field they are already fixing reads as a
    // second failure.
    expect(find.textContaining('could not find'), findsNothing);
  });

  testWidgets('cannot be submitted twice while it is working', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return null;
      },
    )));

    await type(tester, 'FH29MR47');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('the heading is announced as a heading', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (_) async => null,
    )));

    expect(find.bySemanticsLabel('Enter the code they gave you'),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets('tells the guardian which characters are not in a code',
      (tester) async {
    await tester.pumpWidget(host(AcceptInvitationScreen(
      onRedeem: (_) async => null,
    )));

    // They are transcribing something they heard. Knowing that O and zero are
    // never in a code resolves most mishearings before they submit.
    expect(find.textContaining('does not contain the letter O'),
        findsOneWidget);
  });

  testWidgets('has a way back when given one', (tester) async {
    // Without onBack the screen had no way out but a valid code, and the
    // system back gesture left the app.
    var back = 0;
    await tester.pumpWidget(MaterialApp(
      home: AcceptInvitationScreen(
        onRedeem: (_) async => null,
        onBack: () => back++,
      ),
    ));
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    expect(back, 1);

    await tester.pumpWidget(MaterialApp(
      home: AcceptInvitationScreen(onRedeem: (_) async => null),
    ));
    expect(find.byTooltip('Back'), findsNothing);
  });
}
