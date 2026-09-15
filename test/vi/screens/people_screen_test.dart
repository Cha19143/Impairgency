import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/vision/faces.dart';
import 'package:impairgency/vi/screens/people_screen.dart';

class Said implements Speaker {
  final said = <String>[];
  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;
  @override
  Future<void> repeat() async {}
  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);
  @override
  Future<void> stop() async {}
}

Friend friend(String name) => Friend(
    id: 'id-$name',
    name: name,
    embeddings: const [
      [1.0]
    ],
    savedAt: DateTime(2026));

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: child));
  await tester.pump();
}

void main() {
  testWidgets('names who is saved, and forgets one', (tester) async {
    final speaker = Said();
    final forgotten = <String>[];
    await pump(
      tester,
      PeopleScreen(
        speaker: speaker,
        friends: [friend('Sam'), friend('Ana')],
        onForget: (f) async => forgotten.add(f.name),
        onForgetEveryone: () async {},
        onBack: () {},
      ),
    );
    expect(speaker.said.join(' '), contains('2 saved: Sam, Ana.'));
    expect(speaker.said.join(' '), contains('only on this phone'));

    await tester.ensureVisible(find.text('Forget Ana'));
    await tester.tap(find.text('Forget Ana'));
    await tester.pumpAndSettle();
    expect(forgotten, ['Ana']);
    expect(speaker.said.last, 'Ana is forgotten.');
  });

  testWidgets('forgetting everyone asks first, with Cancel ready',
      (tester) async {
    var everyone = 0;
    await pump(
      tester,
      PeopleScreen(
        friends: [friend('Sam'), friend('Ana')],
        onForget: (_) async {},
        onForgetEveryone: () async => everyone++,
        onBack: () {},
      ),
    );
    await tester.tap(find.text('Forget everyone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(everyone, 0);

    await tester.tap(find.text('Forget everyone'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Forget everyone'));
    await tester.pumpAndSettle();
    expect(everyone, 1);
  });

  testWidgets('with recognition off, how to turn it on', (tester) async {
    await pump(
      tester,
      PeopleScreen(
        consented: false,
        friends: const [],
        onForget: (_) async {},
        onForgetEveryone: () async {},
        onBack: () {},
      ),
    );
    expect(find.textContaining('Recognising people is off'), findsOneWidget);
  });
}
