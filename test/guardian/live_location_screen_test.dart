import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/guardian/watched_user.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/guardian/screens/live_location_screen.dart';

/// The map that follows one person. The map itself is a placeholder here;
/// what is asserted is what the guardian is told around it.
void main() {
  final now = DateTime.utc(2026, 9, 13, 9);

  Widget host(Stream<WatchedUser?> user,
          {void Function(LocationFix)? onOpenMap, VoidCallback? onBack}) =>
      MaterialApp(
        theme: buildAppTheme(),
        home: LiveLocationScreen(
          user: user,
          now: () => now,
          onBack: onBack ?? () {},
          onOpenMap: onOpenMap,
          mapBuilder: (fix) => Text('map at ${fix.latitude}'),
        ),
      );

  testWidgets('says loading, then where they are, then follows a new fix',
      (tester) async {
    final user = StreamController<WatchedUser?>();
    addTearDown(user.close);
    await tester.pumpWidget(host(user.stream));
    expect(find.text('Loading…'), findsOneWidget);

    user.add(const WatchedUser(uid: 'u1', name: 'Ana', sharesLocation: true));
    await tester.pump();
    expect(find.text('Ana'), findsOneWidget);
    expect(find.textContaining('none has been recorded'), findsOneWidget);
    expect(find.textContaining('map at'), findsNothing);

    user.add(WatchedUser(
      uid: 'u1',
      name: 'Ana',
      sharesLocation: true,
      fix: LocationFix(
          latitude: 14.79,
          longitude: 120.92,
          accuracyMetres: 12,
          at: now.subtract(const Duration(seconds: 40))),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('map at 14.79'), findsOneWidget);
    expect(find.textContaining('Updated'), findsOneWidget);
    expect(find.textContaining('within 12 metres'), findsOneWidget);

    user.add(WatchedUser(
      uid: 'u1',
      name: 'Ana',
      sharesLocation: true,
      fix: LocationFix(
          latitude: 14.80, longitude: 120.92, accuracyMetres: 8, at: now),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('map at 14.8'), findsOneWidget);
  });

  testWidgets('hands the fix to the maps app, and has a way back',
      (tester) async {
    LocationFix? opened;
    var back = 0;
    final fix = LocationFix(
        latitude: 14.79, longitude: 120.92, accuracyMetres: 12, at: now);
    await tester.pumpWidget(host(
      Stream.value(WatchedUser(uid: 'u1', sharesLocation: true, fix: fix)),
      onOpenMap: (f) => opened = f,
      onBack: () => back++,
    ));
    await tester.pump();
    await tester.tap(find.text('Open in your maps app'));
    expect(opened, same(fix));
    await tester.tap(find.byTooltip('Back'));
    expect(back, 1);
  });
}
