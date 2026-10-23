import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/voice/screen_flow.dart';
import 'package:impairgency/core/voice/spoken_email.dart';
import 'package:impairgency/core/voice/verify_email_flow.dart';
import 'package:impairgency/core/voice/yes_no.dart';
import 'package:impairgency/data/auth_service.dart';
import 'package:impairgency/vi/onboarding/verify_email_screen.dart';

class _RecordingSpeaker implements Speaker {
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

void main() {
  group('yes or no', () {
    test('yes, yeah, and correct are yes', () {
      expect(parseYesNo('yes'), YesNo.yes);
      expect(parseYesNo('Yeah'), YesNo.yes);
      expect(parseYesNo('correct'), YesNo.yes);
      expect(parseYesNo('yes please'), YesNo.yes);
    });

    test('no and nope are no', () {
      expect(parseYesNo('no'), YesNo.no);
      expect(parseYesNo('Nope'), YesNo.no);
    });

    test('okay, done, and keep it are not a yes', () {
      expect(parseYesNo('okay'), isNull);
      expect(parseYesNo('ok'), isNull);
      expect(parseYesNo('done'), isNull);
      expect(parseYesNo('keep it'), isNull);
      expect(parseYesNo('sure'), isNull);
    });
  });

  group('check your email', () {
    VerifyEmailFlow open({String? email = 'ben@example.com', bool linkSent = true}) {
      final flow = VerifyEmailFlow(email: email, linkSent: linkSent);
      final opening = flow.opening();
      expect(opening.listen, isTrue);
      expect(opening.step, VerifyEmailStep.askAction);
      return flow;
    }

    test('the opening says the address aloud and names the three actions', () {
      final flow = VerifyEmailFlow(email: 'ben@example.com');
      final opening = flow.opening();
      final said = opening.lines.join(' ');
      expect(opening.lines.first, 'Check your email');
      expect(said, contains(spokenEmailAloud('ben@example.com')));
      expect(said, isNot(contains('ben@example.com')));
      expect(said, contains('I have confirmed my email'));
      expect(said, contains('Send the link again'));
      expect(said, contains('Use a different email'));
    });

    test('no address on the account is said as your email address', () {
      for (final email in [null, '', '   ']) {
        final said = VerifyEmailFlow(email: email).opening().lines.join(' ');
        expect(said, contains('your email address'));
      }
    });

    test('a link that has not been sent names Send me the link', () {
      final said =
          VerifyEmailFlow(email: 'ben@example.com', linkSent: false)
              .opening()
              .lines
              .join(' ');
      expect(said, contains('Send me the link'));
      expect(said, isNot(contains('We sent a link')));
    });

    test('confirmed, and the other ways to say it, call the check', () {
      const phrases = [
        'I have confirmed my email',
        'confirmed',
        'I confirmed my email',
        'I already confirmed my email',
      ];
      for (final phrase in phrases) {
        final flow = open();
        expect(
          interpretVerifyEmailReply(flow.step, phrase),
          VerifyEmailCommand.confirmed,
        );
        final move = flow.advance(VerifyEmailCommand.confirmed);
        expect(move.check, isTrue);
        expect(move.lines, isEmpty);
        expect(move.signOut, isFalse);
      }
    });

    test('a failed check adds one sentence and does not repeat the error', () {
      final flow = open();
      final again = flow.afterChecked(verified: false);
      expect(again.lines, [kAfterCheckLine]);
      expect(again.listen, isTrue);
      expect(again.lines.single, isNot(contains('not confirmed yet')));
      expect(again.lines.single, isNot(contains('Could not check')));
    });

    test('a verified address adds no sentence', () {
      final flow = open();
      final done = flow.afterChecked(verified: true);
      expect(done.step, VerifyEmailStep.done);
      expect(done.lines, isEmpty);
      expect(done.stop, isTrue);
      expect(done.listen, isFalse);
    });

    test('resend calls the handler, and a sent link adds one sentence', () {
      final flow = open();
      expect(
        interpretVerifyEmailReply(flow.step, 'resend'),
        VerifyEmailCommand.resend,
      );
      expect(
        interpretVerifyEmailReply(flow.step, 'Send the link again'),
        VerifyEmailCommand.resend,
      );
      final asking = flow.advance(VerifyEmailCommand.resend);
      expect(asking.resend, isTrue);
      expect(asking.lines, isEmpty);

      final sent = flow.afterResent(sent: true);
      expect(sent.lines, [kOpenItLine]);
      expect(sent.lines.single, isNot(contains('on its way')));
      expect(sent.listen, isTrue);
    });

    test('a cooldown or a refused resend is not followed by the sent line', () {
      final flow = open();
      final again = flow.afterResent(sent: false);
      expect(again.lines.single, contains('Send the link again'));
      expect(again.lines.join(' '), isNot(contains(kOpenItLine)));
    });

    test('a different email asks before it signs out', () {
      final flow = open();
      expect(
        interpretVerifyEmailReply(flow.step, 'Use a different email'),
        VerifyEmailCommand.differentEmail,
      );
      final asked = flow.advance(VerifyEmailCommand.differentEmail);
      expect(asked.step, VerifyEmailStep.confirmSignOut);
      expect(asked.lines, [kSignOutLine]);
      expect(asked.signOut, isFalse);
      expect(asked.listen, isTrue);
    });

    test('only yes signs out, and no goes back to the actions', () {
      final flow = open();
      flow.advance(VerifyEmailCommand.differentEmail);

      expect(
        interpretVerifyEmailReply(flow.step, 'yes'),
        VerifyEmailCommand.yes,
      );
      final leaving = flow.advance(VerifyEmailCommand.yes);
      expect(leaving.signOut, isTrue);
      expect(leaving.lines, isEmpty);

      final stayed = open();
      stayed.advance(VerifyEmailCommand.differentEmail);
      final back = stayed.advance(VerifyEmailCommand.no);
      expect(back.signOut, isFalse);
      expect(back.step, VerifyEmailStep.askAction);
      expect(back.listen, isTrue);
    });

    test('okay, done, and keep it do not sign out', () {
      for (final phrase in ['okay', 'done', 'keep it', 'sure']) {
        final flow = open();
        flow.advance(VerifyEmailCommand.differentEmail);
        expect(interpretVerifyEmailReply(flow.step, phrase),
            VerifyEmailCommand.unclear);
        final missed = flow.advance(VerifyEmailCommand.unclear);
        expect(missed.signOut, isFalse);
        expect(missed.lines.first, kMissedLine);
      }
    });

    test('yes on the action question is not a sign-out', () {
      final flow = open();
      expect(
        interpretVerifyEmailReply(flow.step, 'yes'),
        VerifyEmailCommand.unclear,
      );
    });

    test('the third miss stops and names the on-screen controls', () {
      final flow = open();
      var move = flow.advance(VerifyEmailCommand.silence);
      expect(move.listen, isTrue);
      expect(move.lines.first, kMissedLine);
      move = flow.advance(VerifyEmailCommand.silence);
      expect(move.listen, isTrue);
      move = flow.advance(VerifyEmailCommand.silence);
      expect(move.stop, isTrue);
      expect(move.listen, isFalse);
      expect(move.lines, contains(kMissedLine));
      expect(move.lines, contains(kTapAButtonLine));
      expect(move.lines, isNot(contains(kGiveUpLine)));
      expect(flow.misses, kVoiceFlowTries);
    });

    test('repeat says the question again, and go back leaves the sign-out', () {
      final flow = open();
      final repeated = flow.advance(VerifyEmailCommand.repeat);
      expect(repeated.listen, isTrue);
      expect(repeated.lines.single, flow.askLine);

      flow.advance(VerifyEmailCommand.differentEmail);
      final back = flow.advance(VerifyEmailCommand.goBack);
      expect(back.signOut, isFalse);
      expect(back.step, VerifyEmailStep.askAction);
    });

    test('coming back asks the current question and does not sign out', () {
      final flow = open();
      flow.advance(VerifyEmailCommand.differentEmail);
      final again = flow.reask();
      expect(again.step, VerifyEmailStep.confirmSignOut);
      expect(again.lines, [kSignOutLine]);
      expect(again.signOut, isFalse);

      final actions = VerifyEmailFlow(email: 'ben@example.com');
      actions.opening();
      expect(actions.reask().lines, [actions.askLine]);
    });
  });

  testWidgets('without VoiceAccess the screen speaks and buttons as before',
      (tester) async {
    final speaker = _RecordingSpeaker();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: VerifyEmailScreen(
        email: 'ben@example.com',
        speaker: speaker,
        onCheck: () async => VerificationCheck.notYet,
        onResend: () async => null,
        onUseDifferentEmail: () {},
      ),
    ));
    await tester.pump();

    expect(speaker.said.first, 'Check your email');
    expect(speaker.said.join(' '), contains('ben@example.com'));
    expect(speaker.said.join(' '), contains('We sent a link'));
    expect(find.text('I have confirmed my email'), findsOneWidget);
    expect(find.text('Send the link again'), findsOneWidget);
    expect(find.text('Use a different email'), findsOneWidget);
    expect(find.text(kSignOutLine), findsNothing);
  });
}
