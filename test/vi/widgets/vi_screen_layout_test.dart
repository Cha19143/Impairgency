import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/vi/screens/settings_screen.dart';
import 'package:impairgency/vi/widgets/vi_button.dart';
import 'package:impairgency/vi/widgets/vi_screen.dart';

/// A screen is the whole screen.
///
/// The bug this file exists for: [ViScreen] laid its text and its actions out
/// as two `Flexible` children of one `Column`. A `Column` divides the space
/// between flexible children by their flex factors *before* laying them out,
/// so with one flex each neither could ever have more than half the phone —
/// and a loose child that used less did not give the rest back. Settings drew
/// its seven choices inside the top half, four of them below the fold, above
/// an empty lower half.

const double _width = 390;
const double _height = 844;

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(_width * 3, _height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: child,
    ),
  ));
  await tester.pump();
}

Widget _settings() => SettingsScreen(
      onConsent: () {},
      onLearned: () {},
      onDevice: () {},
      onEmergencyContact: () {},
      onInviteGuardian: () {},
      onSafetyNotice: () {},
      onBack: () {},
      hasContact: true,
    );

/// More choices than any phone has room for, so the actions area is always the
/// one asking for more than it can have. Deliberately not a real screen: what
/// is being measured is the space it is given, which must not depend on how a
/// font happens to wrap on the machine running the test.
Widget _crowded({String title = 'Settings'}) => ViScreen(
      title: title,
      actions: [
        for (var i = 0; i < 12; i++)
          ViButton(label: 'Choice $i', onPressed: () {}),
      ],
    );

/// The two scrollable regions, top one first.
(Rect, Rect) _regions(WidgetTester tester) {
  final found = find.byType(Scrollable).evaluate().toList();
  expect(found, hasLength(2));
  return (
    tester.getRect(find.byWidget(found.first.widget)),
    tester.getRect(find.byWidget(found.last.widget)),
  );
}

void main() {
  testWidgets('choices that do not fit still get all the screen there is',
      (tester) async {
    await pump(tester, _crowded());
    final (text, actions) = _regions(tester);

    expect(text.top, 0, reason: 'the title starts at the top');
    expect(actions.top, text.bottom, reason: 'nothing dead in between');
    expect(actions.bottom, _height, reason: 'and nothing dead underneath');
    expect(actions.height, greaterThan(_height * 0.85),
        reason: 'the choices were held to half a screen again');
  });

  testWidgets('the same at 2.0x text scale', (tester) async {
    await pump(tester, _crowded(), textScale: 2.0);
    expect(tester.takeException(), isNull);

    final (text, actions) = _regions(tester);
    expect(actions.bottom, _height);
    expect(actions.height, greaterThan(_height * 0.75));
    expect(text.height, greaterThan(0),
        reason: 'the title has to survive too — a screen with no title is a '
            'screen a user cannot place');
  });

  testWidgets('every choice on Settings can be reached', (tester) async {
    await pump(tester, _settings());

    for (final label in const [
      'Emergency contact',
      'Guardian',
      'What the app is using',
      'What the app has learned',
      'Connect a device',
      'What this app can and cannot do',
      'Back',
    ]) {
      final finder = find.widgetWithText(ViButton, label);
      expect(finder, findsOneWidget, reason: '$label is missing');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final rect = tester.getRect(finder);
      expect(rect.top, greaterThanOrEqualTo(0.0), reason: label);
      expect(rect.bottom, lessThanOrEqualTo(_height), reason: label);
    }
  });

  testWidgets('the title stays put while the choices scroll', (tester) async {
    await pump(tester, _settings(), textScale: 2.0);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.getRect(find.text('Settings')).top, lessThan(_height / 4));
  });

  testWidgets('a title-only screen puts its choices under the title',
      (tester) async {
    await pump(
      tester,
      ViScreen(
        title: 'Settings',
        actions: [ViButton(label: 'Emergency contact', onPressed: () {})],
      ),
    );

    final (text, _) = _regions(tester);
    final first = tester.getRect(find.byType(ViButton));
    expect(first.top - text.bottom, lessThan(24),
        reason: 'a list of choices should not float below a hole');
  });

  testWidgets('with something to read, the choices sit at the bottom',
      (tester) async {
    await pump(
      tester,
      ViScreen(
        title: 'Welcome',
        body: const ['One short line.'],
        actions: [
          ViButton(label: 'Continue', onPressed: () {}),
          ViButton(
            label: 'Not now',
            kind: ViButtonKind.quiet,
            onPressed: () {},
          ),
        ],
      ),
    );

    expect(tester.getRect(find.text('Welcome')).top, lessThan(_height / 4));
    expect(tester.getRect(find.byType(ViButton).last).bottom,
        greaterThan(_height - 48),
        reason: 'the primary action should be where a thumb lands');
  });

  testWidgets('a long body scrolls rather than pushing the actions off',
      (tester) async {
    await pump(
      tester,
      ViScreen(
        title: 'Consent',
        body: List.filled(12, 'A paragraph that is here to take up room. ' * 3),
        actions: [ViButton(label: 'I agree', onPressed: () {})],
      ),
    );

    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.byType(ViButton));
    expect(button.bottom, lessThanOrEqualTo(_height));
    expect(button.top, greaterThan(_height / 2));
  });
}
