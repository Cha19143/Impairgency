import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/admin_shell.dart';

const phone = Size(420, 900);
const desktop = Size(1280, 900);

Future<void> pump(
  WidgetTester tester, {
  Size size = desktop,
  String? account,
  VoidCallback? onSignOut,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAdminTheme(),
    home: AdminShell(
      current: '/admin/overview',
      title: 'Overview',
      subtitle: 'Last 30 days',
      account: account,
      onSelect: (_) {},
      onSignOut: onSignOut ?? () {},
      child: const Text('the pane'),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('carries the product mark at every width', (tester) async {
    // The sign-in page opens with this lockup; the dashboard behind the door
    // should look like the door.
    await pump(tester);
    expect(find.byType(AdminBrandMark), findsOneWidget);

    await pump(tester, size: phone);
    expect(find.byType(AdminBrandMark), findsOneWidget,
        reason: 'the app bar carries it once the sidebar is a drawer');
  });

  group('the signed-in account', () {
    testWidgets('is named in the sidebar', (tester) async {
      // There is a whole screen for the case where someone is signed in as an
      // account they did not mean to be. Naming it is how that gets noticed.
      await pump(tester, account: 'dex@example.com');
      expect(find.text('dex@example.com'), findsOneWidget);
    });

    testWidgets('is named in the drawer too', (tester) async {
      await pump(tester, size: phone, account: 'dex@example.com');
      expect(find.text('dex@example.com'), findsNothing,
          reason: 'the drawer is closed');

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('dex@example.com'), findsOneWidget);
    });

    testWidgets('is left out rather than guessed at when unknown',
        (tester) async {
      await pump(tester);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('the way out is still there', (tester) async {
      var signedOut = false;
      await pump(tester, account: 'dex@example.com',
          onSignOut: () => signedOut = true);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
    });
  });

  testWidgets('the page heading is announced as a heading', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(find.bySemanticsLabel('Overview'), findsWidgets);
    handle.dispose();
  });

  testWidgets('each section is a button to a screen reader, the open one selected',
      (tester) async {
    // A bare InkWell was announced as its text alone: nothing said it could be
    // pressed, and nothing said which section was open.
    final semantics = tester.ensureSemantics();
    await pump(tester);

    SemanticsNode nav(String label) => tester.getSemantics(find.descendant(
        of: find.byType(AdminNav), matching: find.text(label)));

    expect(
        nav('Overview'),
        isSemantics(
            label: 'Overview',
            isButton: true,
            isSelected: true,
            hasTapAction: true));
    expect(
        nav('Users'),
        isSemantics(
            label: 'Users',
            isButton: true,
            isSelected: false,
            hasTapAction: true));
    semantics.dispose();
  });
}
