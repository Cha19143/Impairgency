import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/safety/safety_notice.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/vi/screens/safety_notice_screen.dart';

/// Records what the app said, which for this app is most of what matters.
class RecordingSpeaker implements Speaker {
  final List<String> said = [];

  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;

  @override
  Future<void> repeat() async {
    if (lastSpoken != null) said.add(lastSpoken!);
  }

  int stops = 0;

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);

  @override
  Future<void> stop() async => stops++;
}

Widget _host(Widget child, {double textScale = 1.0}) => MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: child,
      ),
    );

void main() {
  testWidgets('speaks the notice on arrival', (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(_host(SafetyNoticeScreen(
      speaker: speaker,
      onAcknowledge: () async {},
    )));
    await tester.pump();

    expect(speaker.said, kSafetyNotice.lines);
  });

  testWidgets('renders the headline and every line', (tester) async {
    await tester.pumpWidget(_host(SafetyNoticeScreen(onAcknowledge: () async {})));
    await tester.pump();

    expect(find.text(kSafetyNotice.headline), findsOneWidget);
    for (final line in kSafetyNotice.lines) {
      expect(find.text(line), findsOneWidget);
    }
  });

  testWidgets('has exactly one control, so it can be finished blind',
      (tester) async {
    await tester.pumpWidget(_host(SafetyNoticeScreen(onAcknowledge: () async {})));
    await tester.pump();

    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('the control carries a semantic label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(SafetyNoticeScreen(onAcknowledge: () async {})));
    await tester.pump();

    expect(
      find.bySemanticsLabel('I understand'),
      findsOneWidget,
      reason: 'a button a blind user cannot hear is not a button',
    );
    handle.dispose();
  });

  testWidgets('acknowledging fires the callback and stops the speech',
      (tester) async {
    var acknowledged = false;
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(_host(SafetyNoticeScreen(
      speaker: speaker,
      onAcknowledge: () async => acknowledged = true,
    )));
    await tester.pump();

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(acknowledged, isTrue);
    expect(speaker.stops, greaterThan(0),
        reason: 'it should stop talking once the user has moved on');
  });

  testWidgets('a revisit offers a way out, not a second acknowledgement',
      (tester) async {
    await tester.pumpWidget(_host(SafetyNoticeScreen(
      alreadyAcknowledged: true,
      onAcknowledge: () async {},
    )));
    await tester.pump();

    expect(find.text('BACK TO MAIN SCREEN'), findsOneWidget);
    expect(find.text('I UNDERSTAND'), findsNothing);
  });

  testWidgets('does not overflow at 2.0x text scale', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(SafetyNoticeScreen(onAcknowledge: () async {}), textScale: 2.0),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the button stays reachable at 2.0x, not scrolled off',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(SafetyNoticeScreen(onAcknowledge: () async {}), textScale: 2.0),
    );
    await tester.pump();

    // The text scrolls; the control does not. Someone who cannot see the screen
    // should not have to scroll to find the only thing on it.
    expect(find.byType(FilledButton), findsOneWidget);
    final button = tester.getRect(find.byType(FilledButton));
    expect(button.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
  });
}
