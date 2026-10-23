import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/screen_flow.dart';

void main() {
  CreateAccountFlow atEmail() {
    final flow = CreateAccountFlow();
    final asked = flow.advance(FlowCommand.continued);
    expect(asked.step, CreateAccountStep.askEmail);
    return flow;
  }

  CreateAccountFlow atConfirm() {
    final flow = atEmail();
    final heard =
        flow.advance(FlowCommand.heard, heard: 'juan at gmail dot com');
    expect(heard.step, CreateAccountStep.confirmEmail);
    expect(heard.email, 'juan@gmail.com');
    return flow;
  }

  CreateAccountFlow atPassword() {
    final flow = atConfirm();
    final next = flow.advance(FlowCommand.keep);
    expect(next.step, CreateAccountStep.askPassword);
    expect(next.focusPassword, isTrue);
    return flow;
  }

  CreateAccountFlow atProceed() {
    final flow = atPassword();
    final next = flow.advance(FlowCommand.done, passwordLength: 8);
    expect(next.step, CreateAccountStep.askProceed);
    return flow;
  }

  test('reading the screen leads to asking for the email', () {
    final flow = CreateAccountFlow();
    expect(flow.openingMove().lines.single, kReadScreenLine);
    expect(flow.openingMove().listen, isFalse);

    final next = flow.advance(FlowCommand.continued);
    expect(next.step, CreateAccountStep.askEmail);
    expect(next.lines.single, kAskEmailLine);
    expect(next.dictate, isTrue);
  });

  test('a spoken email is read back and can be kept', () {
    final flow = atConfirm();
    expect(
      flow.promptFor(CreateAccountStep.confirmEmail),
      'I heard: j u a n at gmail dot com. Keep it, say it again, or spell it?',
    );

    final next = flow.advance(FlowCommand.keep);
    expect(next.step, CreateAccountStep.askPassword);
    expect(next.lines.single, kAskPasswordLine);
    expect(next.focusPassword, isTrue);
  });

  test('an incomplete email is asked for again', () {
    final flow = atEmail();
    flow.advance(FlowCommand.heard, heard: 'juan at gmail');
    final next = flow.advance(FlowCommand.keep);
    expect(next.step, CreateAccountStep.askEmail);
    expect(next.lines.first, kEmailInvalidLine);
    expect(next.lines.last, kAskEmailLine);
  });

  test('say it again returns to the email', () {
    final flow = atConfirm();
    final next = flow.advance(FlowCommand.again);
    expect(next.step, CreateAccountStep.askEmail);
    expect(next.lines.first, kSayEmailAgainLine);
    expect(next.lines.last, kAskEmailLine);
  });

  test('spell it captures letters and confirms them', () {
    final flow = atConfirm();
    final spelling = flow.advance(FlowCommand.spell);
    expect(spelling.step, CreateAccountStep.spellEmail);
    expect(spelling.lines.single, kSpellEmailLine);
    expect(spelling.dictate, isTrue);

    final heard =
        flow.advance(FlowCommand.heard, heard: 'j u a n at gmail dot com');
    expect(flow.email, 'juan@gmail.com');
    expect(heard.step, CreateAccountStep.confirmEmail);
  });

  test('a short password is counted and not accepted', () {
    final flow = atPassword();
    final next = flow.advance(FlowCommand.done, passwordLength: 3);
    expect(next.step, CreateAccountStep.askPassword);
    expect(
      next.lines.first,
      'That is only 3 characters. It needs at least eight. Please type it again.',
    );
    expect(next.lines.last, kAskPasswordLine);
    expect(next.focusPassword, isTrue);
  });

  test('eight characters is enough to ask to proceed', () {
    final flow = atPassword();
    final next = flow.advance(FlowCommand.done, passwordLength: 8);
    expect(next.step, CreateAccountStep.askProceed);
    expect(next.lines.first, 'I see you typed 8 characters.');
    expect(next.lines.last, kAskProceedLine);
    expect(next.focusPassword, isFalse);
  });

  test('create account submits from the proceed prompt', () {
    final flow = atProceed();
    final next = flow.advance(FlowCommand.createAccount);
    expect(next.submit, isTrue);
    expect(next.listen, isFalse);
  });

  test('change my email and change my password leave the proceed prompt', () {
    final email = atProceed().advance(FlowCommand.changeEmail);
    expect(email.step, CreateAccountStep.askEmail);

    final password = atProceed().advance(FlowCommand.changePassword);
    expect(password.step, CreateAccountStep.askPassword);
    expect(password.focusPassword, isTrue);
  });

  test('repeat reads the current prompt again and is not a miss', () {
    final flow = atEmail();
    flow.advance(FlowCommand.silence);
    expect(flow.misses, 1);

    final again = flow.advance(FlowCommand.repeat);
    expect(flow.misses, 1);
    expect(again.step, CreateAccountStep.askEmail);
    expect(again.lines.single, kAskEmailLine);
    expect(again.listen, isTrue);
  });

  test('go back moves to the previous input', () {
    final spelled = atConfirm().advance(FlowCommand.spell);
    expect(spelled.step, CreateAccountStep.spellEmail);
    expect(
      atConfirm().advance(FlowCommand.spell).step,
      CreateAccountStep.spellEmail,
    );

    final flow = atConfirm()..advance(FlowCommand.spell);
    expect(flow.advance(FlowCommand.goBack).step, CreateAccountStep.confirmEmail);
    expect(flow.advance(FlowCommand.goBack).step, CreateAccountStep.askEmail);
    expect(flow.advance(FlowCommand.goBack).step, CreateAccountStep.askEmail);

    final password = atPassword();
    expect(
      password.advance(FlowCommand.goBack).step,
      CreateAccountStep.confirmEmail,
    );

    final proceed = atProceed();
    expect(
      proceed.advance(FlowCommand.goBack).step,
      CreateAccountStep.askPassword,
    );
  });

  test('the third miss suggests the mic or the keyboard and stops', () {
    final flow = atEmail();
    final first = flow.advance(FlowCommand.silence);
    expect(first.listen, isTrue);
    expect(first.lines.first, kMissedLine);
    expect(flow.misses, 1);

    flow.advance(FlowCommand.unclear);
    expect(flow.misses, 2);

    final third = flow.advance(FlowCommand.silence);
    expect(flow.misses, 3);
    expect(third.stop, isTrue);
    expect(third.listen, isFalse);
    expect(third.lines, [kMissedLine, kGiveUpLine, kAskEmailLine]);
  });

  test('a failed account creation returns to the field it names', () {
    final flow = atProceed();
    expect(
      flow
          .afterFailure(
              'There is already an account with that email. Try signing in instead.')
          .step,
      CreateAccountStep.askEmail,
    );
    expect(
      flow
          .afterFailure(
              'That password is too easy to guess. Use at least eight characters.')
          .step,
      CreateAccountStep.askPassword,
    );
    expect(
      flow
          .afterFailure('No connection. Check your network and try again.')
          .step,
      CreateAccountStep.askProceed,
    );
  });

  test('password words other than done are dropped', () {
    expect(
      interpretAccountReply(CreateAccountStep.askPassword, 'correct horse'),
      FlowCommand.unclear,
    );
    expect(
      interpretAccountReply(CreateAccountStep.askPassword, 'done'),
      FlowCommand.done,
    );
    expect(
      interpretAccountReply(CreateAccountStep.confirmEmail, 'say it again'),
      FlowCommand.again,
    );
    expect(
      interpretAccountReply(CreateAccountStep.confirmEmail, 'keep it'),
      FlowCommand.keep,
    );
    expect(
      interpretAccountReply(CreateAccountStep.confirmEmail, 'spell it'),
      FlowCommand.spell,
    );
  });
}
