import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/safety/safety_notice.dart';
import 'package:impairgency/core/session_store.dart';

/// Drives the real router rather than its pieces.
///
/// Every one of these covers a gap that unit tests could not see: the redirect
/// rule and the screens were each correct on their own, and the app still stuck
/// on its first screen. That bug reached a simulator.
Future<AppSession> pumpApp(
  WidgetTester tester, {
  bool acknowledged = false,
}) async {
  final session = AppSession(
    store: InMemorySessionStore(acknowledged: acknowledged),
  );
  await session.load();
  await tester.pumpWidget(MaterialApp.router(
    theme: buildAppTheme(),
    routerConfig: createRouter(session),
  ));
  await tester.pumpAndSettle();
  return session;
}

void main() {
  testWidgets('a first run opens on the safety notice', (tester) async {
    await pumpApp(tester);
    expect(find.text(kSafetyNotice.headline), findsOneWidget);
  });

  testWidgets('acknowledging actually moves the user on', (tester) async {
    // The bug this exists for: resolveRedirect deliberately allows /safety once
    // acknowledged, so the dashboard can reopen it - which meant nothing moved
    // the user off it on first run. Both halves were right; the app was stuck.
    final session = await pumpApp(tester);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(session.state.safetyAcknowledged, isTrue);
    expect(find.text(kSafetyNotice.headline), findsNothing,
        reason: 'the notice should not still be on screen');
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('the acknowledgement is remembered across a restart',
      (tester) async {
    final session = await pumpApp(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Same store, fresh router - what a relaunch looks like.
    final relaunched = AppSession(store: session.store);
    await relaunched.load();
    await tester.pumpWidget(MaterialApp.router(
      theme: buildAppTheme(),
      routerConfig: createRouter(relaunched),
    ));
    await tester.pumpAndSettle();

    expect(find.text(kSafetyNotice.headline), findsNothing);
  });

  testWidgets('an already-acknowledged user never sees it again',
      (tester) async {
    await pumpApp(tester, acknowledged: true);
    expect(find.text(kSafetyNotice.headline), findsNothing);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('the notice can be reopened later without being re-acknowledged',
      (tester) async {
    // The notice promises "you can hear this again at any time", so reopening
    // it must not put the user back through onboarding.
    final session = await pumpApp(tester, acknowledged: true);
    final router = createRouter(session);
    await tester.pumpWidget(MaterialApp.router(
      theme: buildAppTheme(),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    router.go(Routes.safety);
    await tester.pumpAndSettle();

    expect(find.text(kSafetyNotice.headline), findsOneWidget);
    expect(find.text('BACK TO MAIN SCREEN'), findsOneWidget);
    expect(find.text('I UNDERSTAND'), findsNothing);
  });
}
