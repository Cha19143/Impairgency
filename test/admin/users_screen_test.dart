import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/users_screen.dart';
import 'package:impairgency/data/admin_repository.dart';

Future<void> pump(
  WidgetTester tester, {
  List<AdminUserRow> users = const [],
  List<UserInvite> invites = const [],
  void Function()? onInvite,
  void Function(UserInvite)? onWithdraw,
}) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAdminTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: UsersScreen(
          users: users,
          invites: invites,
          onInvite: onInvite,
          onWithdraw: onWithdraw,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

const roster = [
  AdminUserRow(
      uid: 'u1',
      role: 'vi',
      displayName: 'Bob Doe',
      email: 'bob@example.com',
      deviceId: 'IG-0041',
      linkedTo: ['g1']),
  AdminUserRow(
      uid: 'g1', role: 'guardian', displayName: 'Ana Reyes', linkedTo: ['u1']),
  AdminUserRow(uid: 'a1', role: 'admin', email: 'admin@example.com'),
];

void main() {
  testWidgets('shows all three roles §1.2 names', (tester) async {
    await pump(tester, users: roster);
    expect(find.text('VI user'), findsOneWidget);
    expect(find.text('Guardian'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('shows device links, and says None rather than blank',
      (tester) async {
    // §1.2 asks admins to manage device connections. It does not ask every
    // account to have one, and an empty cell reads as missing data.
    await pump(tester, users: roster);
    expect(find.text('IG-0041'), findsOneWidget);
    expect(find.text('None'), findsNWidgets(2));
  });

  testWidgets('counts who each account is linked to', (tester) async {
    await pump(tester, users: roster);
    expect(find.text('1'), findsNWidgets(2), reason: 'Bob and Ana are linked');
    expect(find.text('—'), findsOneWidget, reason: 'the admin is linked to nobody');
  });

  testWidgets('falls back to the email when there is no display name',
      (tester) async {
    await pump(tester, users: roster);
    expect(find.text('admin@example.com'), findsWidgets);
  });

  testWidgets('reports how many accounts there are', (tester) async {
    await pump(tester, users: roster);
    expect(find.text('3 accounts'), findsOneWidget);

    await pump(tester, users: [roster.first]);
    expect(find.text('1 account'), findsOneWidget);
  });

  testWidgets('an empty roster says so', (tester) async {
    await pump(tester);
    expect(find.text('No accounts yet.'), findsOneWidget);
  });

  group('invitations', () {
    const pending = [
      UserInvite(email: 'new@example.com', role: 'guardian'),
    ];

    testWidgets('lists who has been invited but not registered',
        (tester) async {
      await pump(tester, users: roster, invites: pending);
      expect(find.text('AWAITING REGISTRATION'), findsOneWidget);
      expect(find.text('new@example.com'), findsOneWidget);
    });

    testWidgets('says plainly that no administrator sees a password',
        (tester) async {
      // The reason invitations exist rather than admin-created accounts.
      await pump(tester, users: roster, invites: pending);
      expect(find.textContaining('choose their own password'), findsOneWidget);
      expect(find.textContaining('Nobody here ever sees it'), findsOneWidget);
    });

    testWidgets('an invitation can be withdrawn', (tester) async {
      UserInvite? withdrawn;
      await pump(
        tester,
        users: roster,
        invites: pending,
        onWithdraw: (i) => withdrawn = i,
      );
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(withdrawn?.email, 'new@example.com');
    });

    testWidgets('the section is hidden when nobody is pending', (tester) async {
      await pump(tester, users: roster);
      expect(find.text('AWAITING REGISTRATION'), findsNothing);
    });

    testWidgets('offers a way to invite someone', (tester) async {
      var tapped = false;
      await pump(tester, users: roster, onInvite: () => tapped = true);
      await tester.tap(find.text('Invite someone'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
