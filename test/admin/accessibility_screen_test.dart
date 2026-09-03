import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/admin_theme.dart';
import 'package:impairgency/admin/screens/accessibility_screen.dart';
import 'package:impairgency/app/theme.dart';

Future<void> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAdminTheme(),
    home: const Scaffold(
      body: SingleChildScrollView(child: AccessibilityScreen()),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows every pair the app actually renders', (tester) async {
    await pump(tester);
    for (final name in kContrastPairs.keys) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('reports the measured ratio, not a claim', (tester) async {
    await pump(tester);
    expect(find.textContaining(':1'), findsWidgets);
    // Pinned deliberately. Dark ink on cyan measures 14.8:1 today; if someone
    // changes the palette this fails and somebody has to look at it, which is
    // the whole point of the page.
    expect(find.text('14.8:1'), findsOneWidget,
        reason: 'label on primary action');
    expect(find.text('17.0:1'), findsOneWidget, reason: 'body text on ground');
    expect(find.text('6.1:1'), findsOneWidget,
        reason: 'label on emergency action - passes AA, below AAA');
  });

  testWidgets('says the palette passes when it passes', (tester) async {
    await pump(tester);
    expect(find.textContaining('Every rendered colour pair meets WCAG AA'),
        findsOneWidget);
    expect(find.text('Fails'), findsNothing);
  });

  testWidgets('grades AAA separately from AA', (tester) async {
    await pump(tester);
    expect(find.text('AAA'), findsWidgets,
        reason: 'the three big action buttons are held to AAA');
  });

  testWidgets('shows a live sample of each pair', (tester) async {
    // A number nobody can see is easy to argue with.
    await pump(tester);
    expect(find.text('Sample'), findsNWidgets(kContrastPairs.length));
  });

  testWidgets('explains where the numbers come from', (tester) async {
    await pump(tester);
    expect(find.textContaining('same constants the app paints with'),
        findsOneWidget);
    expect(find.textContaining('§4'), findsOneWidget);
  });

  testWidgets('is not the old audits button that audited nothing',
      (tester) async {
    await pump(tester);
    expect(find.textContaining('Audit'), findsNothing);
  });
}
