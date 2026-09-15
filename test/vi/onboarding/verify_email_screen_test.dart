import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/data/auth_service.dart';
import 'package:impairgency/vi/onboarding/verify_email_screen.dart';

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

void main() {
  Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

  testWidgets('says where the link went, and what to do', (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(VerifyEmailScreen(
      email: 'ben@example.com',
      speaker: speaker,
      onCheck: () async => VerificationCheck.notYet,
      onResend: () async => null,
      onUseDifferentEmail: () {},
    )));
    await tester.pump();
    expect(speaker.said.first, 'Check your email');
    expect(speaker.said.join(' '), contains('ben@example.com'));
  });

  testWidgets('never claims a link was sent that was not', (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(VerifyEmailScreen(
      email: 'ben@example.com',
      linkSent: false,
      speaker: speaker,
      onCheck: () async => VerificationCheck.notYet,
      onResend: () async => null,
      onUseDifferentEmail: () {},
    )));
    await tester.pump();
    expect(speaker.said.join(' '), isNot(contains('We sent a link')));
    expect(find.text('Send me the link'), findsOneWidget);
  });

  testWidgets('pressing too early explains, rather than doing nothing',
      (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(VerifyEmailScreen(
      email: 'ben@example.com',
      speaker: speaker,
      onCheck: () async => VerificationCheck.notYet,
      onResend: () async => null,
      onUseDifferentEmail: () {},
    )));
    await tester.tap(find.text('I have confirmed my email'));
    await tester.pumpAndSettle();
    expect(speaker.said.last, VerifyEmailScreen.notYet);
    expect(find.text(VerifyEmailScreen.notYet), findsOneWidget);
  });

  testWidgets('a second link waits out the cooldown, and says so',
      (tester) async {
    final speaker = RecordingSpeaker();
    var sends = 0;
    var now = DateTime.utc(2026, 9, 15, 9);
    await tester.pumpWidget(host(VerifyEmailScreen(
      email: 'ben@example.com',
      speaker: speaker,
      now: () => now,
      onCheck: () async => VerificationCheck.notYet,
      onResend: () async {
        sends++;
        return null;
      },
      onUseDifferentEmail: () {},
    )));
    await tester.tap(find.text('Send the link again'));
    await tester.pump();
    expect(sends, 1);
    expect(speaker.said.last, contains('on its way to ben@example.com'));

    now = now.add(const Duration(seconds: 10));
    await tester.tap(find.text('Send the link again'));
    await tester.pump();
    expect(sends, 1);
    expect(speaker.said.last, contains('50 seconds'));

    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.text('Send the link again'));
    await tester.pump();
    expect(sends, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a refused resend is said in its own words', (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(VerifyEmailScreen(
      email: 'ben@example.com',
      speaker: speaker,
      onCheck: () async => VerificationCheck.failed,
      onResend: () async => 'Too many links have been sent.',
      onUseDifferentEmail: () {},
    )));
    await tester.tap(find.text('Send the link again'));
    await tester.pump();
    expect(speaker.said.last, 'Too many links have been sent.');
  });
}
