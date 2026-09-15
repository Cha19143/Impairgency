import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/vi/widgets/vi_button.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('a screen reader, switch or voice command can press it',
      (tester) async {
    // What TalkBack's fallback hid: the announced node had no tap action, so
    // anything that presses a button through accessibility - Voice Access's
    // "tap Scan", Switch Access, a keyboard - found a label and nothing to do.
    final handle = tester.ensureSemantics();
    var pressed = 0;
    await tester.pumpWidget(host(ViButton(
      label: 'Scan',
      detail: 'Describe what is in front of you',
      onPressed: () => pressed++,
    )));

    tester.semantics.tap(find.semantics
        .byLabel('Scan. Describe what is in front of you'));
    await tester.pump();

    expect(pressed, 1);
    handle.dispose();
  });

  testWidgets('a disabled button offers nothing to press', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const ViButton(label: 'Read', onPressed: null)));

    final node = tester.getSemantics(find.byType(ViButton));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });
}
