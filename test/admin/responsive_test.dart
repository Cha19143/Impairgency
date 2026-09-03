import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/accessibility_screen.dart';
import 'package:impairgency/admin/screens/admin_shell.dart';
import 'package:impairgency/admin/screens/overview_screen.dart';
import 'package:impairgency/admin/screens/system_health_screen.dart';
import 'package:impairgency/admin/screens/users_screen.dart';
import 'package:impairgency/core/places/session_summary.dart';
import 'package:impairgency/data/admin_repository.dart';

const phone = Size(375, 812);
const tablet = Size(768, 1024);
const desktop = Size(1440, 900);
const wide = Size(2560, 1400);

final _overview = UsageOverview(
  activeUsers: 12,
  sessions: 340,
  sosIncidents: 3,
  frequentPlaceLabels: const [
    (label: 'Home', count: 41),
    (label: 'Barangay clinic', count: 18),
  ],
  detectionCounts: const [
    (kind: 'obstacleDetected', count: 260),
    (kind: 'stairsDetected', count: 47),
  ],
  medianDiscardedFraction: 0.06,
);

const _users = [
  AdminUserRow(
      uid: 'u1',
      role: 'vi',
      displayName: 'Bob Doe',
      email: 'bob@example.com',
      deviceId: 'IG-0041',
      linkedTo: ['g1']),
  AdminUserRow(uid: 'g1', role: 'guardian', displayName: 'Ana Reyes'),
  AdminUserRow(uid: 'a1', role: 'admin', email: 'admin@example.com'),
];

Map<String, Widget> panes() => {
      'Overview': OverviewScreen(overview: _overview),
      'Users': const UsersScreen(
        users: _users,
        invites: [UserInvite(email: 'new@example.com', role: 'guardian')],
      ),
      'System health': SystemHealthScreen(
        overview: _overview,
        sessionsNeedingAttention: const [],
      ),
      'Accessibility': const AccessibilityScreen(),
    };

Future<void> pump(
  WidgetTester tester,
  Widget pane, {
  required Size size,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: buildAdminTheme(),
    home: AdminShell(
      current: '/admin/overview',
      title: 'Overview',
      onSelect: (_) {},
      onSignOut: () {},
      child: pane,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in panes().entries) {
    group(entry.key, () {
      for (final size in [phone, tablet, desktop, wide]) {
        testWidgets('lays out at ${size.width.toInt()} wide', (tester) async {
          await pump(tester, entry.value, size: size);
          expect(tester.takeException(), isNull,
              reason: '${entry.key} overflowed at ${size.width}');
        });
      }
    });
  }

  group('navigation survives every width', () {
    testWidgets('a phone gets a drawer, and it is reachable', (tester) async {
      // The narrow layout used to drop the sidebar and put nothing in its
      // place, leaving every section but the current one unreachable.
      await pump(tester, panes()['Overview']!, size: phone);

      final menu = find.byTooltip('Open navigation menu');
      expect(menu, findsOneWidget, reason: 'no way to open the navigation');

      await tester.tap(menu);
      await tester.pumpAndSettle();

      for (final section in adminSections) {
        expect(find.text(section.label), findsWidgets,
            reason: '${section.label} unreachable on a phone');
      }
    });

    testWidgets('choosing a section closes the drawer', (tester) async {
      // Leaving it open over the page it just navigated to hides the thing the
      // user asked for.
      AdminSection? chosen;
      tester.view.physicalSize = phone * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildAdminTheme(),
        home: AdminShell(
          current: '/admin/overview',
          title: 'Overview',
          onSelect: (s) => chosen = s,
          child: OverviewScreen(overview: _overview),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();

      expect(chosen?.label, 'Users');
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('a desktop gets the sidebar, not a drawer', (tester) async {
      await pump(tester, panes()['Overview']!, size: desktop);
      expect(find.byTooltip('Open navigation menu'), findsNothing);
      expect(find.byType(AdminNav), findsOneWidget);
      for (final section in adminSections) {
        // findsWidgets, not findsOneWidget: "Overview" is both a nav item and
        // the page title.
        expect(find.text(section.label), findsWidgets,
            reason: '${section.label} missing from the sidebar');
      }
    });
  });

  group('content does not sprawl on a very wide monitor', () {
    testWidgets('it stops growing past the cap', (tester) async {
      await pump(tester, panes()['Accessibility']!, size: wide);

      // Without a cap a table row stretches the full window and puts the number
      // a long way from the label it belongs to.
      final body = tester.getRect(find.text('body text on ground'));
      expect(body.width, lessThan(kAdminMaxContentWidth));
    });
  });

  group('the panes actually change shape', () {
    testWidgets('the users table drops its header row on a phone',
        (tester) async {
      await pump(tester, panes()['Users']!, size: desktop);
      expect(find.text('DEVICE'), findsOneWidget);

      await pump(tester, panes()['Users']!, size: phone);
      expect(find.text('DEVICE'), findsNothing,
          reason: 'four columns do not fit; the rows label themselves instead');
      expect(find.textContaining('Device: IG-0041'), findsOneWidget);
      expect(find.textContaining('Linked to 1'), findsOneWidget);
    });

    testWidgets('KPI cards fill the row rather than sitting at a fixed width',
        (tester) async {
      final handle = tester.ensureSemantics();

      await pump(tester, panes()['Overview']!, size: phone);
      // Measured on the card, not its label. A phone gets one per row, so the
      // card should be the content width less padding - well past the 208 it
      // used to be pinned at.
      final onPhone =
          tester.getRect(find.bySemanticsLabel('Active users: 12')).width;
      expect(onPhone, greaterThan(300),
          reason: 'one card per row on a phone, using the width available');

      await pump(tester, panes()['Overview']!, size: desktop);
      final onDesktop =
          tester.getRect(find.bySemanticsLabel('Active users: 12')).width;
      expect(onDesktop, lessThan(onPhone),
          reason: 'four across on a desktop, so each is narrower');

      handle.dispose();
    });
  });
}
