import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/contacts/emergency_contact.dart';
import 'package:impairgency/core/sos/sos_receipt.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/voice/voice_commands.dart';
import 'package:impairgency/vi/screens/sos_countdown_screen.dart';
import 'package:impairgency/vi/screens/sos_receipt_screen.dart';

class RecordingSpeaker implements Speaker {
  final List<String> said = [];

  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;

  @override
  Future<void> repeat() async {
    if (lastSpoken != null) said.add(lastSpoken!);
  }

  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);
  @override
  Future<void> stop() async {}
}

Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

void main() {
  group('the arming countdown — cancel has to mean cancel', () {
    testWidgets('nothing fires while it is still counting', (tester) async {
      var fired = false;
      await tester.pumpWidget(host(SosCountdownScreen(
        onFire: () => fired = true,
        onCancel: () {},
        contactName: 'Mum',
      )));
      await tester.pump(const Duration(seconds: 2));
      expect(fired, isFalse, reason: 'ui.pdf dialled first and cancelled after');
    });

    testWidgets('fires when the countdown runs out', (tester) async {
      var fired = false;
      await tester.pumpWidget(host(SosCountdownScreen(
        onFire: () => fired = true,
        onCancel: () {},
      )));
      await tester.pump(const Duration(seconds: 4));
      expect(fired, isTrue);
    });

    testWidgets('the whole screen cancels, not just the button',
        (tester) async {
      // Someone who has put the phone in their pocket cannot find a button,
      // but they can slap the glass.
      var cancelled = false;
      var fired = false;
      await tester.pumpWidget(host(SosCountdownScreen(
        onFire: () => fired = true,
        onCancel: () => cancelled = true,
      )));
      await tester.tapAt(const Offset(200, 120));
      await tester.pump(const Duration(seconds: 5));

      expect(cancelled, isTrue);
      expect(fired, isFalse);
    });

    testWidgets('the cancel button cancels', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(host(SosCountdownScreen(
        onFire: () {},
        onCancel: () => cancelled = true,
      )));
      await tester.tap(find.text('CANCEL'));
      await tester.pump();
      expect(cancelled, isTrue);
    });

    testWidgets('a spoken cancel stops it', (tester) async {
      final voice = StreamController<VoiceCommand>();
      addTearDown(voice.close);
      var cancelled = false;
      var fired = false;

      await tester.pumpWidget(host(SosCountdownScreen(
        onFire: () => fired = true,
        onCancel: () => cancelled = true,
        voice: voice.stream,
      )));
      voice.add(VoiceCommand.cancel);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(cancelled, isTrue);
      expect(fired, isFalse);
    });

    testWidgets('saying "help" during the countdown does NOT cancel it',
        (tester) async {
      // Saying help during an SOS means the user wants help. Stopping the SOS
      // would be the exact opposite of what they asked for.
      final voice = StreamController<VoiceCommand>();
      addTearDown(voice.close);
      var cancelled = false;
      var fired = false;

      await tester.pumpWidget(host(SosCountdownScreen(
        onFire: () => fired = true,
        onCancel: () => cancelled = true,
        voice: voice.stream,
      )));
      voice.add(VoiceCommand.help);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(cancelled, isFalse);
      expect(fired, isTrue);
    });

    testWidgets('counts down out loud and says how to stop it', (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(SosCountdownScreen(
        onFire: () {},
        onCancel: () {},
        contactName: 'Mum',
        speaker: speaker,
      )));
      await tester.pump(const Duration(seconds: 2));

      expect(speaker.said.first, 'Calling Mum in 3.');
      expect(speaker.said, contains('Calling Mum in 2.'));
      expect(speaker.said.join(' '), contains('Say cancel'));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('cancelling says that nothing happened', (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(SosCountdownScreen(
        onFire: () {},
        onCancel: () {},
        speaker: speaker,
      )));
      await tester.tap(find.text('CANCEL'));
      await tester.pump();
      expect(speaker.said.join(' '), contains('Nothing was sent'));
    });

    testWidgets('cannot fire twice, or fire after being cancelled',
        (tester) async {
      var fires = 0;
      var cancels = 0;
      await tester.pumpWidget(host(SosCountdownScreen(
        onFire: () => fires++,
        onCancel: () => cancels++,
      )));
      await tester.tap(find.text('CANCEL'));
      await tester.tapAt(const Offset(200, 120));
      await tester.pump(const Duration(seconds: 6));

      expect(cancels, 1);
      expect(fires, 0);
    });
  });

  group('the receipt', () {
    SosReceipt receipt({
      LegOutcome call = LegOutcome.done,
      LegOutcome guardians = LegOutcome.done,
    }) =>
        SosReceipt([
          const LegResult(SosLeg.alarm, LegOutcome.done),
          LegResult(SosLeg.call, call, detail: 'Mum'),
          const LegResult(SosLeg.location, LegOutcome.done,
              detail: 'Your location was sent.'),
          LegResult(SosLeg.guardians, guardians),
        ]);

    testWidgets('speaks itself on arrival', (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(SosReceiptScreen(
        receipt: receipt(),
        onDone: () {},
        speaker: speaker,
      )));
      await tester.pump();
      expect(speaker.said.single, receipt().spoken);
    });

    testWidgets('a failed leg is shown as failed, in the words it speaks',
        (tester) async {
      final r = receipt(call: LegOutcome.failed);
      await tester.pumpWidget(
          host(SosReceiptScreen(receipt: r, onDone: () {})));
      await tester.pump();

      expect(find.text('The call to Mum did not connect.'), findsOneWidget);
      expect(find.text('Nobody was reached'), findsNothing,
          reason: 'the guardian was still told');
    });

    testWidgets('when nobody was reached it says so at the top',
        (tester) async {
      final r = receipt(
          call: LegOutcome.failed, guardians: LegOutcome.notConfigured);
      await tester.pumpWidget(
          host(SosReceiptScreen(receipt: r, onDone: () {})));
      await tester.pump();

      expect(find.text('Nobody was reached'), findsOneWidget);
    });

    testWidgets('offers Try again only when nobody was reached',
        (tester) async {
      await tester.pumpWidget(host(SosReceiptScreen(
        receipt: receipt(),
        onDone: () {},
        onCallAgain: () {},
      )));
      await tester.pump();
      expect(find.text('Try again'), findsNothing);

      await tester.pumpWidget(host(SosReceiptScreen(
        receipt: receipt(
            call: LegOutcome.failed, guardians: LegOutcome.notConfigured),
        onDone: () {},
        onCallAgain: () {},
      )));
      await tester.pump();
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offers the next person on the list, and a text to all',
        (tester) async {
      var next = 0;
      var texted = 0;
      await tester.pumpWidget(host(SosReceiptScreen(
        receipt: receipt(),
        onDone: () {},
        nextContact: const EmergencyContact(name: 'Dad', number: '0918'),
        onCallNext: () => next++,
        contactCount: 3,
        onTextAll: () => texted++,
      )));
      await tester.pump();

      await tester.tap(find.text('Call Dad'));
      await tester.tap(find.text('Text all 3 contacts'));
      expect(next, 1);
      expect(texted, 1);
    });

    testWidgets('with nobody left to call, no next button', (tester) async {
      await tester.pumpWidget(host(SosReceiptScreen(
        receipt: receipt(),
        onDone: () {},
        contactCount: 1,
        onTextAll: () {},
      )));
      await tester.pump();
      expect(find.textContaining('Call '), findsNothing);
      expect(find.text('Text your contact'), findsOneWidget);
    });

    testWidgets('every leg appears on screen', (tester) async {
      await tester.pumpWidget(
          host(SosReceiptScreen(receipt: receipt(), onDone: () {})));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsNWidgets(4));
    });
  });
}
