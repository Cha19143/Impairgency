import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/pairing/pairing_code.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/guardian/guardian_registration.dart';
import 'package:impairgency/guardian/screens/guardian_register_screen.dart';

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

String? validate({
  String name = 'Ben',
  String email = 'ben@example.com',
  String password = 'longenough',
  String phone = '+63 917 000 0000',
  String code = 'FH29 MR47',
}) =>
    validateGuardianRegistration(
      name: name,
      email: email,
      password: password,
      phone: phone,
      pairingCode: code,
    );

void main() {
  group('what the form refuses', () {
    test('a complete form passes', () => expect(validate(), isNull));
    test('name', () => expect(validate(name: ' '), contains('name')));
    test('email', () => expect(validate(email: 'ben'), contains('email')));
    test('password',
        () => expect(validate(password: 'short'), contains('eight')));
    test('phone', () => expect(validate(phone: '12'), contains('phone')));
    test('the code is checked by shape before anything is sent', () {
      expect(validate(code: 'FH29MR4O'), contains('letter O'));
      expect(validate(code: 'FH29'), contains('eight characters'));
    });
  });

  test('the phone is stored the way the dialler wants it', () {
    expect(normalisePhone('+63 (917) 000-0000'), '+639170000000');
  });

  test('the account document says guardian, and nothing else decides it', () {
    const r = GuardianRegistration(
      name: ' Ben ',
      email: 'ben@example.com',
      password: 'x',
      phone: '0917',
      pairingCode: 'FH29MR47',
    );
    final doc = r.toUserDocument('g1');
    expect(doc['role'], 'guardian');
    expect(doc['uid'], 'g1');
    expect(doc['name'], 'Ben');
    expect(doc['displayName'], 'Ben');
    expect(doc['phone'], '0917');
    expect(doc.containsKey('password'), isFalse);
    expect(doc.containsKey('pairingCode'), isFalse,
        reason: 'the code is redeemed, not stored on the account');
  });

  group('the screen', () {
    Widget host(Widget child) =>
        MaterialApp(theme: buildAppTheme(), home: child);

    Future<void> fill(WidgetTester tester, {String code = 'FH29MR47'}) async {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Ben');
      await tester.enterText(fields.at(1), 'ben@example.com');
      await tester.enterText(fields.at(2), 'longenough');
      await tester.enterText(fields.at(3), '0917 000 0000');
      await tester.enterText(fields.at(4), code);
    }

    TextField field(WidgetTester tester, int index) =>
        tester.widget<TextField>(find.byType(TextField).at(index));

    testWidgets('hands over every field, normalised', (tester) async {
      GuardianRegistration? sent;
      await tester.pumpWidget(host(GuardianRegisterScreen(
        onRegister: (r) async {
          sent = r;
          return null;
        },
        onRegistered: () {},
        onSignIn: () {},
      )));
      await fill(tester, code: 'fh29 mr47');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      expect(sent!.pairingCode, 'FH29MR47');
      expect(sent!.phone, '09170000000');
      expect(sent!.name, 'Ben');
    });

    testWidgets('a linked account leaves the form for the dashboard',
        (tester) async {
      // The tester's report: the code was right, the account was made, the
      // link was written - and the screen stayed exactly as it was, so they
      // pressed Create account again and were told the account existed.
      var opened = 0;
      await tester.pumpWidget(host(GuardianRegisterScreen(
        onRegister: (_) async => null,
        onRegistered: () => opened++,
        onSignIn: () {},
      )));
      await fill(tester);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets(
        'a code the server refuses is said, shown under the code, and only '
        'the code is asked for again', (tester) async {
      final speaker = RecordingSpeaker();
      final refusal =
          pairingRejectionMessage(PairingCodeRejection.alreadyUsed);
      var opened = 0;
      await tester.pumpWidget(host(GuardianRegisterScreen(
        speaker: speaker,
        onRegister: (_) async => RegisterFailure(refusal,
            field: RegisterField.code, accountReady: true),
        onRegistered: () => opened++,
        onSignIn: () {},
      )));
      await fill(tester);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(field(tester, 4).decoration!.errorText, refusal);
      expect(speaker.said, contains(refusal));
      expect(opened, 0);
      // The account exists now. Name, email, password and phone made it, so
      // they are locked, and the button no longer offers to create anything.
      for (final i in [0, 1, 2, 3]) {
        expect(field(tester, i).enabled, isFalse, reason: 'field $i');
      }
      expect(field(tester, 4).enabled, isTrue);
      expect(find.text('Create account'), findsNothing);
      expect(find.text('Link with this code'), findsOneWidget);
      expect(find.text('I already have an account'), findsNothing);
    });

    testWidgets('an email refusal sits under the email, not the code',
        (tester) async {
      const refusal = 'There is already an account with that email. Press "I '
          'already have an account" to sign in, then enter the code.';
      await tester.pumpWidget(host(GuardianRegisterScreen(
        onRegister: (_) async =>
            const RegisterFailure(refusal, field: RegisterField.email),
        onRegistered: () {},
        onSignIn: () {},
      )));
      await fill(tester);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(field(tester, 1).decoration!.errorText, refusal);
      expect(field(tester, 4).decoration!.errorText, isNull);
      expect(field(tester, 1).enabled, isTrue,
          reason: 'no account was made, so the email can still be changed');
    });

    testWidgets('a failure that throws is said, and the button comes back',
        (tester) async {
      final speaker = RecordingSpeaker();
      await tester.pumpWidget(host(GuardianRegisterScreen(
        speaker: speaker,
        onRegister: (_) async => throw StateError('offline'),
        onRegistered: () {},
        onSignIn: () {},
      )));
      await fill(tester);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(speaker.said.last, contains('Check your connection'));
      expect(find.text('Creating your account…'), findsNothing);
      expect(find.text('Create account'), findsOneWidget);
    });

    testWidgets('a malformed code never reaches the server', (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(GuardianRegisterScreen(
        onRegister: (_) async {
          calls++;
          return null;
        },
        onRegistered: () {},
        onSignIn: () {},
      )));
      await fill(tester, code: 'FH29');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.textContaining('eight characters'), findsWidgets);
    });

    testWidgets('the code field refuses characters that are not in a code',
        (tester) async {
      await tester.pumpWidget(host(GuardianRegisterScreen(
        onRegister: (_) async => null,
        onRegistered: () {},
        onSignIn: () {},
      )));
      await tester.enterText(find.byType(TextField).at(4), 'fh0o29');
      expect(
        (tester.widget(find.byType(TextField).at(4)) as TextField)
            .controller!
            .text,
        'FH29',
      );
    });
  });
}
