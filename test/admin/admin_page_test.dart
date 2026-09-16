import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/admin_page.dart';
import 'package:impairgency/admin/screens/admin_shell.dart';

void main() {
  testWidgets('reloading keeps the last page on screen until the next one lands',
      (tester) async {
    // Every add, edit and remove reloads the users page. Blanking it to a
    // spinner each time would lose the administrator's place in the table.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var loads = 0;
    Completer<String>? pending;
    Future<void> Function()? reload;

    await tester.pumpWidget(MaterialApp(
      theme: buildAdminTheme(),
      home: AdminPage<String>(
        route: '/admin/users',
        title: 'Users',
        load: () {
          loads++;
          if (loads == 1) return Future.value('first');
          pending = Completer<String>();
          return pending!.future;
        },
        builder: (context, data, again) {
          reload = again;
          return Text('data: $data');
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('data: first'), findsOneWidget);

    unawaited(reload!());
    await tester.pump();
    expect(find.text('data: first'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    pending!.complete('second');
    await tester.pumpAndSettle();
    expect(find.text('data: second'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required Future<String> Function() load,
    void Function(AdminSection)? onSelect,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAdminTheme(),
      home: AdminPage<String>(
        route: '/admin/users',
        title: 'Users',
        load: load,
        builder: (context, data, _) => Text('data: $data'),
        onSelect: onSelect ?? (_) {},
      ),
    ));
  }

  testWidgets('an unreachable database is not blamed on the roster',
      (tester) async {
    // Every failure used to say the account was probably not an
    // administrator - including an administrator whose connection dropped.
    await pumpPage(tester,
        load: () => Future.error(Exception(
            '[cloud_firestore/unavailable] Failed to get documents because '
            'the client is offline.')));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the database'), findsOneWidget);
    expect(find.textContaining('admin roster'), findsNothing);
  });

  testWidgets('a refusal still says what a refusal usually means',
      (tester) async {
    await pumpPage(tester,
        load: () => Future.error(Exception(
            '[cloud_firestore/permission-denied] Missing or insufficient '
            'permissions.')));
    await tester.pumpAndSettle();

    expect(find.textContaining('not on the admin roster'), findsOneWidget);
  });

  testWidgets('a load that hangs ends in words', (tester) async {
    // A Firestore read with no connection can wait for ever. A spinner that
    // never resolves is the state this page exists not to show.
    await pumpPage(tester, load: () => Completer<String>().future);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(kAdminLoadTimeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Could not reach the database'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('clicking the current section reloads it', (tester) async {
    // go_router ignores a move to the page already open, and nothing
    // animates, so this click used to do nothing anyone could see.
    var loads = 0;
    final pending = <Completer<String>>[];
    AdminSection? navigatedTo;
    await pumpPage(
      tester,
      load: () {
        loads++;
        if (loads == 1) return Future.value('first');
        pending.add(Completer<String>());
        return pending.last.future;
      },
      onSelect: (section) => navigatedTo = section,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(AdminNav), matching: find.text('Users')));
    await tester.pump();

    expect(loads, 2);
    expect(navigatedTo, isNull, reason: 'the page it is on is not a move');
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: 'the reload is visible while it runs');

    pending.single.complete('second');
    await tester.pumpAndSettle();
    expect(find.text('data: second'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(AdminNav), matching: find.text('Overview')));
    await tester.pump();
    expect(navigatedTo?.route, '/admin/overview',
        reason: 'another section still navigates');
    expect(loads, 2);
  });
}
