import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/contacts/emergency_contact.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/data/contact_picker.dart';
import 'package:impairgency/vi/onboarding/emergency_contact_screen.dart';

class RecordingSpeaker implements Speaker {
  final List<String> said = [];
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

class FakePicker implements ContactPicker {
  FakePicker(this.outcome);
  final ContactPickOutcome outcome;
  int picks = 0;
  @override
  Future<ContactPickOutcome> pick() async {
    picks++;
    return outcome;
  }
}

Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

Future<void> type(WidgetTester tester, String name, String number) async {
  await tester.enterText(find.byType(TextField).at(0), name);
  await tester.enterText(find.byType(TextField).at(1), number);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adds people one at a time and reads the order back',
      (tester) async {
    final speaker = RecordingSpeaker();
    List<EmergencyContact>? saved;
    await tester.pumpWidget(host(EmergencyContactScreen(
      speaker: speaker,
      onSave: (c) => saved = c,
      onSkip: () {},
    )));

    await type(tester, 'Mum', '0917 000 0000');
    await tapText(tester, 'Add this person');
    expect(speaker.said.last, 'Mum added. Mum will be called.');

    await type(tester, 'Dad', '0918 000 0000');
    await tapText(tester, 'Add this person');
    expect(speaker.said.last, 'Dad added. Mum will be called first, then Dad.');

    await tapText(tester, 'Save these 2 contacts');
    expect(saved!.map((c) => c.name), ['Mum', 'Dad']);
  });

  testWidgets('a typed but un-added person is not lost on Save',
      (tester) async {
    List<EmergencyContact>? saved;
    await tester.pumpWidget(host(EmergencyContactScreen(
      onSave: (c) => saved = c,
      onSkip: () {},
    )));
    await type(tester, 'Mum', '0917 000 0000');
    await tapText(tester, 'Save');
    expect(saved!.single.name, 'Mum');
  });

  testWidgets('the order can be changed, and the change is spoken',
      (tester) async {
    final speaker = RecordingSpeaker();
    List<EmergencyContact>? saved;
    await tester.pumpWidget(host(EmergencyContactScreen(
      speaker: speaker,
      initial: const [
        EmergencyContact(name: 'Mum', number: '0917'),
        EmergencyContact(name: 'Dad', number: '0918'),
      ],
      onSave: (c) => saved = c,
      onSkip: () {},
    )));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel(
        'Move Dad up, so they are called sooner'));
    await tester.pumpAndSettle();
    expect(speaker.said.last, 'Dad will be called first, then Mum.');

    await tapText(tester, 'Save these 2 contacts');
    expect(saved!.map((c) => c.name), ['Dad', 'Mum']);
  });

  testWidgets('a person can be removed', (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(EmergencyContactScreen(
      speaker: speaker,
      initial: const [
        EmergencyContact(name: 'Mum', number: '0917'),
        EmergencyContact(name: 'Dad', number: '0918'),
      ],
      onSave: (_) {},
      onSkip: () {},
    )));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Remove Dad'));
    await tester.pumpAndSettle();
    expect(speaker.said.last, 'Dad removed. Mum will be called.');
    expect(find.text('Dad'), findsNothing);
  });

  testWidgets('choosing from the phone adds the person chosen',
      (tester) async {
    final speaker = RecordingSpeaker();
    final picker = FakePicker(const ContactPicked(
        EmergencyContact(name: 'Ate Liza', number: '+63 919 000 0000')));
    await tester.pumpWidget(host(EmergencyContactScreen(
      speaker: speaker,
      picker: picker,
      onSave: (_) {},
      onSkip: () {},
    )));
    await tapText(tester, 'Choose from my contacts');

    expect(picker.picks, 1);
    expect(find.text('Ate Liza'), findsOneWidget);
    expect(speaker.said.last, contains('Ate Liza'));
    expect(speaker.said.last, contains('will be called'));
  });

  testWidgets('a picker that cannot open says so, and typing still works',
      (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(EmergencyContactScreen(
      speaker: speaker,
      picker: FakePicker(const ContactPickUnavailable(
          'Choosing from contacts is not available on this device. You can '
          'type the number instead.')),
      onSave: (_) {},
      onSkip: () {},
    )));
    await tapText(tester, 'Choose from my contacts');
    expect(speaker.said.last, contains('type the number instead'));
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('cancelling the picker is not an error', (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(EmergencyContactScreen(
      speaker: speaker,
      picker: FakePicker(const ContactPickCancelled()),
      onSave: (_) {},
      onSkip: () {},
    )));
    await tapText(tester, 'Choose from my contacts');
    expect(speaker.said.last, contains('No contact was chosen'));
  });

  testWidgets('without a picker, the option is not offered', (tester) async {
    await tester.pumpWidget(host(EmergencyContactScreen(
      onSave: (_) {},
      onSkip: () {},
    )));
    expect(find.text('Choose from my contacts'), findsNothing);
  });

  testWidgets('the same number twice is refused, out loud', (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(EmergencyContactScreen(
      speaker: speaker,
      initial: const [EmergencyContact(name: 'Mum', number: '0917 000 0000')],
      onSave: (_) {},
      onSkip: () {},
    )));
    await type(tester, 'Mother', '09170000000');
    await tapText(tester, 'Add this person');
    expect(speaker.said.last, contains('Mum already has that number'));
  });

  testWidgets('skipping still warns first', (tester) async {
    final speaker = RecordingSpeaker();
    var skipped = false;
    await tester.pumpWidget(host(EmergencyContactScreen(
      speaker: speaker,
      onSave: (_) {},
      onSkip: () => skipped = true,
    )));
    await tapText(tester, 'Skip for now');
    expect(skipped, isFalse);
    expect(speaker.said.last, contains('nobody to call'));
    await tapText(tester, 'Skip anyway');
    expect(skipped, isTrue);
  });

  testWidgets('the form goes away at the limit, with a way to make room',
      (tester) async {
    final full = List.generate(kMaxEmergencyContacts,
        (i) => EmergencyContact(name: 'Person $i', number: '091700000$i'));
    await tester.pumpWidget(host(EmergencyContactScreen(
      initial: full,
      onSave: (_) {},
      onSkip: () {},
    )));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('Remove Person 0'), findsOneWidget);
  });
}
