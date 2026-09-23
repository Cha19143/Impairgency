import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/admin_shell.dart';
import 'package:impairgency/admin/screens/overview_screen.dart';
import 'package:impairgency/core/places/session_summary.dart';

UsageOverview overview({
  int users = 12,
  int sessions = 340,
  int sos = 3,
  List<({String label, int count})> places = const [
    (label: 'Home', count: 41),
    (label: 'clinic', count: 18),
  ],
  List<({String kind, int count})> detections = const [
    (kind: 'obstacleDetected', count: 260),
    (kind: 'stairsDetected', count: 47),
  ],
  double discard = 0.06,
}) =>
    UsageOverview(
      activeUsers: users,
      sessions: sessions,
      sosIncidents: sos,
      frequentPlaceLabels: places,
      detectionCounts: detections,
      medianDiscardedFraction: discard,
    );

Future<void> pump(WidgetTester tester, UsageOverview data,
    {Size size = const Size(1280, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAdminTheme(),
    home: AdminShell(
      current: '/admin/overview',
      title: 'Overview',
      child: OverviewScreen(overview: data),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the numbers it was given, and no others', (tester) async {
    // The screen this replaces hardcoded 15.4K, 99.2% and 14ms, and looked
    // entirely convincing. Every figure here has to come from the data.
    await pump(tester, overview());

    expect(find.text('12'), findsOneWidget);
    expect(find.text('340'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('15.4K'), findsNothing);
    expect(find.text('99.2%'), findsNothing);
    expect(find.text('14ms'), findsNothing);
  });

  testWidgets('all five §1.3 metrics are present', (tester) async {
    await pump(tester, overview());

    expect(find.text('ACTIVE USERS'), findsOneWidget);
    expect(find.text('NAVIGATION SESSIONS'), findsOneWidget);
    expect(find.text('SOS INCIDENTS'), findsOneWidget);
    expect(find.text('FREQUENTLY VISITED PLACES'), findsOneWidget);
    expect(find.text('DETECTIONS'), findsOneWidget);
  });

  testWidgets('an SOS above zero is marked as needing attention',
      (tester) async {
    await pump(tester, overview(sos: 0));
    final calm = tester.widget<Text>(find.text('0'));
    expect(calm.style?.color, AdminColors.ink);

    await pump(tester, overview(sos: 2));
    final alarmed = tester.widget<Text>(find.text('2'));
    expect(alarmed.style?.color, AdminColors.bad);
  });

  testWidgets('positioning quality is the inverse of what was discarded',
      (tester) async {
    await pump(tester, overview(discard: 0.06));
    expect(find.text('94%'), findsOneWidget);
  });

  testWidgets('shows a dash rather than 100% when there is nothing to measure',
      (tester) async {
    await pump(tester, overview(sessions: 0, discard: 0));
    // 100% positioning quality from zero sessions would be a lie of the exact
    // kind this dashboard exists to stop telling.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
  });

  testWidgets('names places the way the user typed them', (tester) async {
    await pump(tester, overview(places: const [
      (label: 'Barangay clinic', count: 9),
      (label: 'Home', count: 30),
    ]));

    expect(find.text('Barangay clinic'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('says that no location data sits behind the places panel',
      (tester) async {
    await pump(tester, overview());
    expect(find.textContaining('No location data is stored here'),
        findsOneWidget);
  });

  testWidgets('never presents detection counts as accuracy', (tester) async {
    await pump(tester, overview());
    expect(find.textContaining('not accuracy'), findsOneWidget);
    expect(find.textContaining('%'), findsWidgets,
        reason: 'positioning quality is a percentage; detections are not');
  });

  testWidgets('translates event kinds into words', (tester) async {
    await pump(tester, overview());
    expect(find.text('Obstacles'), findsOneWidget);
    expect(find.text('Stairs'), findsOneWidget);
    expect(find.text('obstacleDetected'), findsNothing);
  });

  testWidgets('an empty period says so rather than showing an empty chart',
      (tester) async {
    await pump(
      tester,
      overview(users: 0, sessions: 0, sos: 0, places: const [], detections: const []),
    );
    expect(find.text('No named places yet.'), findsOneWidget);
    expect(find.text('Nothing detected yet.'), findsOneWidget);
  });

  testWidgets('KPI cards are announced as a label and a value', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, overview());
    expect(find.bySemanticsLabel('Active users: 12'), findsOneWidget);
    expect(find.bySemanticsLabel('SOS incidents: 3'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('stacks the panels on a narrow window without overflowing',
      (tester) async {
    await pump(tester, overview(), size: const Size(700, 1000));
    expect(tester.takeException(), isNull);
    expect(find.text('FREQUENTLY VISITED PLACES'), findsOneWidget);
  });

  testWidgets('with no journeys, says why rather than showing a blank',
      (tester) async {
    await pump(tester, overview(sessions: 0, places: const [], detections: const []));
    expect(find.text(kNoJourneysExplanation), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'SOS are still counted');
  });

  testWidgets('with journeys, no explanation is needed', (tester) async {
    await pump(tester, overview());
    expect(find.text(kNoJourneysExplanation), findsNothing);
  });
}
