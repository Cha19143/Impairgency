import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/vi/onboarding/create_account_screen.dart';
import 'package:impairgency/vi/voice_controller.dart';
import 'package:impairgency/vi/widgets/dictated_field.dart';
import 'package:impairgency/vi/widgets/vi_screen.dart';
import 'package:impairgency/vi/widgets/voice_access.dart';
import 'package:impairgency/vi/widgets/voice_form.dart';
import 'package:impairgency/vi/widgets/voice_mic_button.dart';

import '../voice_fakes.dart';

Future<void> pumpWithVoice(
    WidgetTester tester, VoiceController? voice, Widget child) async {
  tester.view.physicalSize = const Size(390, 1600) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: VoiceAccess(voice: voice, child: child),
  ));
  await tester.pump();
}

/// Lets the app act on what the microphone heard.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('a field is filled in by voice, and only after a yes',
      (tester) async {
    final mic = OpenWindows();
    final speaker = Recording();
    final voice = voiceControllerFor(mic, speaker);
    final email = TextEditingController();
    addTearDown(email.dispose);

    await pumpWithVoice(
      tester,
      voice,
      Scaffold(
        body: DictatedField(
          label: 'Email address',
          controller: email,
          shape: DictationShape.email,
          field: TextField(controller: email),
        ),
      ),
    );

    await tester.tap(find.text('Say the email address'));
    await settle(tester);
    expect(speaker.said.last, 'Say the email address.');

    mic.say(const Heard('j d e x at gmail dot com'));
    await settle(tester);
    expect(speaker.said.last,
        'Email address: j d e x at gmail dot com. Say done to keep it, add '
        'and more, delete last word, spell it, or say it again.');
    expect(email.text, isEmpty, reason: 'nothing is kept before the yes');
    expect(find.textContaining('Heard: j d e x at gmail dot com'),
        findsNothing, reason: 'the window it was heard in has closed');

    mic.say(const Heard('yes'));
    await settle(tester);
    expect(email.text, 'jdex@gmail.com');
  });

  testWidgets('without a microphone, the field is only the field',
      (tester) async {
    final name = TextEditingController();
    addTearDown(name.dispose);
    await pumpWithVoice(
      tester,
      null,
      Scaffold(
        body: DictatedField(
          label: 'Name',
          controller: name,
          field: TextField(controller: name),
        ),
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Say the'), findsNothing);
  });

  testWidgets('Create account offers the email by voice, never the password',
      (tester) async {
    final voice = voiceControllerFor(OpenWindows(), Recording());
    await pumpWithVoice(
      tester,
      voice,
      CreateAccountScreen(onCreate: (_, __) async => null),
    );
    expect(find.text('Say the email address'), findsOneWidget);
    expect(find.textContaining('Say the password'), findsNothing);
    expect(find.byType(VoiceMicButton), findsOneWidget,
        reason: 'the screen offers the microphone');
  });

  testWidgets('fill in asks for the empty fields in order, then names the '
      'button', (tester) async {
    final mic = OpenWindows();
    final speaker = Recording();
    final voice = voiceControllerFor(mic, speaker);
    final name = TextEditingController();
    final phone = TextEditingController();
    final done = TextEditingController(text: 'already said');
    addTearDown(name.dispose);
    addTearDown(phone.dispose);
    addTearDown(done.dispose);

    await pumpWithVoice(
      tester,
      voice,
      ViScreen(
        title: 'Who should we call?',
        mic: false,
        extra: VoiceForm(
          submitLabel: 'Add this person',
          child: Column(
            children: [
              DictatedField(
                label: 'Name',
                controller: name,
                shape: DictationShape.name,
                field: TextField(controller: name),
              ),
              DictatedField(
                label: 'Notes',
                controller: done,
                field: TextField(controller: done),
              ),
              DictatedField(
                label: 'Phone number',
                controller: phone,
                shape: DictationShape.phone,
                field: TextField(controller: phone),
              ),
            ],
          ),
        ),
        actions: const [],
      ),
    );

    final listening = voice.listen();
    await settle(tester);
    mic.say(const Heard('fill in'));
    await settle(tester);
    expect(speaker.said.last, 'Say the name.');

    mic.say(const Heard('ana cruz'));
    await settle(tester);
    mic.say(const Heard('yes'));
    await settle(tester);
    expect(name.text, 'Ana Cruz');
    expect(speaker.said.last, 'Say the phone number.',
        reason: 'the filled-in field in between is not asked again');

    mic.say(const Heard('0917 123 4567'));
    await settle(tester);
    mic.say(const Heard('yes'));
    await settle(tester);
    expect(phone.text, '09171234567');
    expect(speaker.said.last, 'Say Add this person when you are ready.');
    await listening;
  });

  testWidgets('a field left unanswered ends the walk, and says how to go on',
      (tester) async {
    final mic = OpenWindows();
    final speaker = Recording();
    final voice = voiceControllerFor(mic, speaker);
    final name = TextEditingController();
    final phone = TextEditingController();
    addTearDown(name.dispose);
    addTearDown(phone.dispose);

    await pumpWithVoice(
      tester,
      voice,
      Scaffold(
        body: VoiceForm(
          child: Column(
            children: [
              DictatedField(
                  label: 'Name',
                  controller: name,
                  field: TextField(controller: name)),
              DictatedField(
                  label: 'Phone number',
                  controller: phone,
                  field: TextField(controller: phone)),
            ],
          ),
        ),
      ),
    );

    final listening = voice.listen();
    await settle(tester);
    mic.say(const Heard('fill in'));
    await settle(tester);
    mic.say(const Heard('cancel'));
    await settle(tester);

    expect(speaker.said.last, 'Say fill in to carry on.');
    expect(mic.open, isFalse, reason: 'the phone number is not asked for');
    await listening;
  });
}
