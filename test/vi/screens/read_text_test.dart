import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/reading/reading_session.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/data/text_reader.dart';
import 'package:impairgency/vi/screens/dashboard_screen.dart';
import 'package:impairgency/vi/screens/read_text_screen.dart';

/// A speaker whose sentences take time, so pausing lands mid-page.
class SlowSpeaker implements Speaker {
  final List<String> said = [];
  int stops = 0;
  Completer<void>? _current;

  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;
  @override
  Future<void> repeat() async => said.add('(repeat)');
  @override
  Future<void> speak(String text) {
    said.add(text);
    _current = Completer<void>();
    return _current!.future;
  }

  /// The engine finished the sentence.
  void finish() {
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);
  @override
  Future<void> stop() async {
    stops++;
    finish();
  }
}

class FakeReader extends TextReader {
  FakeReader({this.text = 'One.\nTwo.\nThree.', this.opens = true});
  final String? text;
  final bool opens;
  int captures = 0;
  @override
  Future<bool> start() async => opens;
  @override
  Future<String?> capture() async {
    captures++;
    return text;
  }

  @override
  Future<void> dispose() async {}
}

Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('reads a page one piece at a time, each to the end',
      (tester) async {
    final speaker = SlowSpeaker();
    await tester.pumpWidget(host(ReadTextScreen(
      speaker: speaker,
      reader: FakeReader(),
      gap: Duration.zero,
      onBack: () {},
    )));
    await settle(tester);
    speaker.finish(); // the intro
    await settle(tester);

    await tester.tap(find.text('Read'));
    await settle(tester);
    speaker.finish(); // "3 lines found. Reading."
    await settle(tester);

    expect(speaker.said.last, 'One.');
    expect(find.textContaining('Line 1 of 3'), findsOneWidget);
    speaker.finish();
    await settle(tester);
    expect(speaker.said.last, 'Two.');
    speaker.finish();
    await settle(tester);
    expect(speaker.said.last, 'Three.');
    speaker.finish();
    await settle(tester);
    expect(speaker.said.last, contains('End of the text'));
  });

  testWidgets('pause stops mid-page, continue picks up the same line',
      (tester) async {
    final speaker = SlowSpeaker();
    await tester.pumpWidget(host(ReadTextScreen(
      speaker: speaker,
      reader: FakeReader(),
      gap: Duration.zero,
      onBack: () {},
    )));
    await settle(tester);
    speaker.finish();
    await tester.tap(find.text('Read'));
    await settle(tester);
    speaker.finish();
    await settle(tester);
    speaker.finish(); // "One." done
    await settle(tester);
    expect(speaker.said.last, 'Two.');

    await tester.tap(find.text('Pause'));
    await settle(tester);
    expect(speaker.said.last, 'Paused.');
    expect(find.textContaining('Paused at line 2 of 3'), findsOneWidget);
    speaker.finish();
    await settle(tester);
    expect(speaker.said.last, 'Paused.', reason: 'nothing read while paused');

    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(speaker.said.last, 'Two.');
  });

  testWidgets('say that again repeats the line just read', (tester) async {
    final speaker = SlowSpeaker();
    await tester.pumpWidget(host(ReadTextScreen(
      speaker: speaker,
      reader: FakeReader(),
      gap: Duration.zero,
      onBack: () {},
    )));
    await settle(tester);
    speaker.finish();
    await tester.tap(find.text('Read'));
    await settle(tester);
    speaker.finish();
    await settle(tester);
    speaker.finish(); // "One." done, cursor now on "Two."
    await settle(tester);

    await tester.tap(find.text('Say that again'));
    await settle(tester);
    expect(speaker.said.last, 'One.');
  });

  testWidgets('a page with no words says so', (tester) async {
    final speaker = SlowSpeaker();
    await tester.pumpWidget(host(ReadTextScreen(
      speaker: speaker,
      reader: FakeReader(text: '  '),
      gap: Duration.zero,
      onBack: () {},
    )));
    await settle(tester);
    speaker.finish();
    await tester.tap(find.text('Read'));
    await settle(tester);
    expect(speaker.said.last, kNothingToRead);
    expect(find.text('Pause'), findsNothing);
  });

  testWidgets('a refused camera is explained, and the way back stays',
      (tester) async {
    final speaker = SlowSpeaker();
    await tester.pumpWidget(host(ReadTextScreen(
      speaker: speaker,
      reader: FakeReader(opens: false),
      onBack: () {},
    )));
    await settle(tester);
    expect(speaker.said.last, contains('camera is turned off'));
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('the dashboard has a separate Read text button', (tester) async {
    var read = 0;
    await tester.pumpWidget(host(DashboardScreen(
      onScan: () {},
      onAssist: () {},
      onSos: () {},
      onWhatCanISay: () {},
      onSettings: () {},
      onReadText: () => read++,
    )));
    await tester.tap(find.text('READ TEXT'));
    expect(read, 1);
    expect(find.text('SCAN ENVIRONMENT'), findsOneWidget,
        reason: 'scan stays what it was');
  });
}
