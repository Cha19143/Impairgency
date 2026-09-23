import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/system_health_screen.dart';
import 'package:impairgency/core/admin/sos_record.dart';
import 'package:impairgency/core/places/session_summary.dart';

final now = DateTime(2026, 9, 18, 12);

const empty = UsageOverview(
  activeUsers: 1,
  sessions: 0,
  sosIncidents: 1,
  frequentPlaceLabels: [],
  detectionCounts: [],
  medianDiscardedFraction: 0,
);

Future<void> pump(
  WidgetTester tester, {
  List<SosRecord> sos = const [],
  Future<void> Function(SosRecord)? onResolve,
  List<Uri>? opened,
}) async {
  tester.view.physicalSize = const Size(1280, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAdminTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: SystemHealthScreen(
          overview: empty,
          sessionsNeedingAttention: const [],
          sosEvents: sos,
          userNames: const {'u1': 'Ana Reyes'},
          onResolve: onResolve,
          now: now,
          openLink: (uri) async => opened?.add(uri),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('says so when there has been no SOS', (tester) async {
    await pump(tester);
    expect(find.text('No SOS in the last 30 days.'), findsOneWidget);
  });

  testWidgets('lists each SOS: who, when, where, who was called, status',
      (tester) async {
    // An SOS fired in front of a tester never reached the dashboard: nothing
    // on it read sos_events.
    final opened = <Uri>[];
    await pump(tester, opened: opened, sos: [
      SosRecord(
        id: 'e1',
        userId: 'u1',
        at: now.subtract(const Duration(minutes: 5)),
        lat: 14.79,
        lng: 120.92,
        locationSummary: 'Your location was sent.',
        contactName: 'Mum',
      ),
      SosRecord(
        id: 'e2',
        userId: 'u9',
        at: now.subtract(const Duration(hours: 2)),
        cancelled: true,
      ),
      SosRecord(
        id: 'e3',
        userId: 'u1',
        at: now.subtract(const Duration(days: 1)),
        resolvedAt: now.subtract(const Duration(hours: 23)),
        resolvedBy: 'user',
      ),
    ]);

    expect(find.text('Ana Reyes'), findsNWidgets(2));
    expect(find.text('u9'), findsOneWidget, reason: 'no name, so the uid');
    expect(find.textContaining('5 minutes ago'), findsOneWidget);
    expect(find.text('Called Mum'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Resolved by user'), findsOneWidget);

    await tester.tap(find.textContaining('Map: 14.79000'));
    expect(opened.single.host, 'www.openstreetmap.org');
  });

  testWidgets('Mark resolved is offered on active rows only, and works',
      (tester) async {
    final resolved = <String>[];
    await pump(
      tester,
      onResolve: (r) async => resolved.add(r.id),
      sos: [
        SosRecord(id: 'e1', userId: 'u1', at: now),
        SosRecord(id: 'e2', userId: 'u1', at: now, resolvedBy: 'user'),
      ],
    );
    expect(find.text('Mark resolved'), findsOneWidget);
    await tester.tap(find.text('Mark resolved'));
    expect(resolved, ['e1']);
  });

  testWidgets('the console links open, rather than asking to be copied',
      (tester) async {
    final opened = <Uri>[];
    await pump(tester, opened: opened);
    await tester.tap(find.textContaining('/crashlytics'));
    expect(opened.single.toString(),
        'https://console.firebase.google.com/project/impairgency-capstone/crashlytics');
  });
}
