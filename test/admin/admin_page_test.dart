import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/admin_page.dart';

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
}
