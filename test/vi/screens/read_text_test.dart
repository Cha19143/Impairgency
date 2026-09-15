import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/reading/reading_session.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/speech/speech_queue.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/data/text_reader.dart';
import 'package:impairgency/vi/screens/dashboard_screen.dart';
import 'package:impairgency/vi/screens/read_text_screen.dart';
import 'package:impairgency/vi/widgets/vi_button.dart';
import 'package:impairgency/vi/widgets/vi_button_group.dart';

import '../voice_fakes.dart';

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

  testWidgets('tells the caller what page was found, once, before reading',
      (tester) async {
    final speaker = SlowSpeaker();
    final read = <String>[];
    await tester.pumpWidget(host(ReadTextScreen(
      speaker: speaker,
      reader: FakeReader(),
      gap: Duration.zero,
      onBack: () {},
      onRead: read.add,
    )));
    await settle(tester);
    speaker.finish();
    await settle(tester);
    expect(read, isEmpty);

    await tester.tap(find.text('Read'));
    await settle(tester);
    expect(read, hasLength(1));
    expect(read.single, isNotEmpty);
  });

  group('by voice', () {
    // The tester: say "read" or "basahin" instead of pressing Read.
    late SlowSpeaker speaker;
    late OpenWindows mic;
    late FakeReader reader;
    late int backs;

    Future<void> open(WidgetTester tester) async {
      speaker = SlowSpeaker();
      mic = OpenWindows();
      reader = FakeReader(text: 'Read the label first.\nShake well.\nKeep cold.');
      backs = 0;
      final voice = voiceControllerFor(mic, speaker)..handsFree = true;
      await tester.pumpWidget(host(ReadTextScreen(
        speaker: speaker,
        reader: reader,
        gap: Duration.zero,
        onBack: () => backs++,
        voice: voice,
      )));
      await settle(tester);
      speaker.finish(); // the intro
      await settle(tester);
    }

    Future<void> hear(WidgetTester tester, String words) async {
      mic.say(Heard(words));
      await settle(tester);
      await tester.pump();
    }

    testWidgets('"basahin" reads what is in front of the camera',
        (tester) async {
      await open(tester);
      expect(speaker.said.first, contains('say read'));
      expect(mic.open, isTrue, reason: 'listening without a tap');

      await hear(tester, 'basahin');
      expect(reader.captures, 1);
      expect(speaker.said.last, '3 lines found. Reading.');
      speaker.finish();
      await settle(tester);
      expect(speaker.said.last, 'Read the label first.');

      // The page, coming back through the microphone, is not a command.
      await hear(tester, 'read the label first');
      await hear(tester, 'read');
      expect(reader.captures, 1);
      expect(speaker.said.last, 'Read the label first.');
    });

    testWidgets('pause, continue, next and again, said', (tester) async {
      await open(tester);
      await hear(tester, 'read');
      speaker.finish(); // "3 lines found. Reading."
      await settle(tester);
      expect(speaker.said.last, 'Read the label first.');

      await hear(tester, 'pause');
      expect(speaker.said.last, 'Paused.');
      expect(find.textContaining('Paused at line 1 of 3'), findsOneWidget);
      speaker.finish();
      await settle(tester);

      await hear(tester, 'ituloy');
      expect(speaker.said.last, 'Read the label first.');

      await hear(tester, 'next');
      expect(speaker.said.last, 'Shake well.');

      await hear(tester, 'say that again');
      expect(speaker.said.last, 'Read the label first.');
    });

    testWidgets('"go back" leaves, but not from the middle of a page',
        (tester) async {
      await open(tester);
      await hear(tester, 'read');
      speaker.finish();
      await settle(tester);

      await hear(tester, 'go back');
      expect(backs, 0, reason: 'while reading, only what controls reading');

      await hear(tester, 'pause');
      speaker.finish();
      await settle(tester);
      await hear(tester, 'go back');
      expect(backs, 1);
    });

    testWidgets('a line that says "next" does not skip a line',
        (tester) async {
      // The page read aloud is heard by the open microphone. The speech queue
      // knows what it said, and those words are not the person's.
      final engine = HeldEngine();
      final queue = SpeechQueue(engine: engine, lineGap: Duration.zero);
      final mic = OpenWindows();
      final voice = voiceControllerFor(mic, queue)..handsFree = true;
      await tester.pumpWidget(host(ReadTextScreen(
        speaker: queue,
        reader: FakeReader(text: 'Next, shake well.\nKeep cold.'),
        gap: Duration.zero,
        onBack: () {},
        voice: voice,
      )));
      await settle(tester);
      engine.finish(); // the intro
      await settle(tester);

      mic.say(const Heard('read'));
      await settle(tester);
      engine.finish(); // "2 lines found. Reading."
      await settle(tester);
      expect(queue.current, 'Next, shake well.');

      mic.say(const Heard('next shake well'));
      await settle(tester);
      expect(queue.current, 'Next, shake well.', reason: 'not cut off');

      engine.finish();
      await settle(tester);
      expect(queue.current, 'Keep cold.', reason: 'the line after it, not two on');
    });
  });

  group('the reading controls on a phone', () {
    // The tester's screenshot: Pause, Say that again and Next line in one row,
    // each label broken a letter or two per line - "Pa / us / e".
    int linesOf(WidgetTester tester, String label) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length));
      return boxes.map((b) => b.top.round()).toSet().length;
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('read as words at ${scale}x text on a 360 dp phone',
          (tester) async {
        tester.view.physicalSize = const Size(360 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        final speaker = SlowSpeaker();
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
                size: const Size(360, 800),
                textScaler: TextScaler.linear(scale)),
            child: ReadTextScreen(
              speaker: speaker,
              reader: FakeReader(),
              gap: Duration.zero,
              onBack: () {},
            ),
          ),
        ));
        await settle(tester);
        speaker.finish();
        await settle(tester);
        await tester.tap(find.text('Read'));
        await settle(tester);

        expect(tester.takeException(), isNull);
        for (final label in ['Pause', 'Say that again', 'Next line']) {
          expect(find.text(label), findsOneWidget);
          // Never more lines than words: a word is never split. At 1x the
          // label also keeps to two lines. (The test font is a full em per
          // letter, far wider than Roboto, so 2x is the strict case.)
          final words = label.split(' ').length;
          expect(linesOf(tester, label),
              lessThanOrEqualTo(scale == 1.0 ? 2 : words),
              reason: '"$label" should not break into pieces');
        }
        // Stacked, so each has the full width to itself.
        final pause = tester.getRect(find.text('Pause'));
        final next = tester.getRect(find.text('Next line'));
        expect(next.top, greaterThan(pause.bottom));
      });
    }

    test('a wide screen keeps them in a row; a phone stacks them', () {
      final buttons = [
        const ViButton(label: 'Pause', icon: Icons.pause, onPressed: null),
        const ViButton(label: 'Say that again', icon: Icons.replay, onPressed: null),
        const ViButton(label: 'Next line', icon: Icons.skip_next, onPressed: null),
      ];
      expect(
        ViButtonGroup.perRow(
            buttons: buttons, width: 1000, textScaler: TextScaler.noScaling),
        3,
      );
      expect(
        ViButtonGroup.perRow(
            buttons: buttons, width: 320, textScaler: TextScaler.noScaling),
        1,
      );
      expect(
        ViButtonGroup.perRow(
            buttons: buttons, width: 1000, textScaler: const TextScaler.linear(3)),
        lessThan(3),
        reason: 'a larger text size needs more room',
      );
    });
  });
}
