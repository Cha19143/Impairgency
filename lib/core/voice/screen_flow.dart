/// One prompt per state, for a screen a person can finish by voice.
///
/// The machine decides the next prompt. It does not speak and it does not
/// open a microphone, so the transitions can be tested without either.
/// Speaking and listening stay in the screen's runner, which calls the
/// app's existing speaker and speech recogniser.
///
/// The next onboarding screen adds its own machine beside [CreateAccountFlow]
/// and a runner that asks this one what to say next. See the README section
/// "Adding the next onboarding voice screen".
library;

import '../auth/email_address.dart';
import 'dictation_edit.dart';
import 'spoken_email.dart';

/// What the person did after a prompt.
enum FlowCommand {
  /// The prompt was spoken and this state does not listen.
  continued,

  /// The microphone heard nothing.
  silence,

  /// Words came back, and they were not an answer to this prompt.
  unclear,

  /// Words to turn into the field's value. The text is passed beside this.
  heard,

  keep,
  again,
  spell,
  done,
  repeat,
  goBack,
  createAccount,
  changeEmail,
  changePassword,
  sayEmail,
  fillIn,
}

/// Where Create your account is in its voice flow.
enum CreateAccountStep {
  readScreen,
  askEmail,
  confirmEmail,
  spellEmail,
  askPassword,
  askProceed,
}

/// What the runner does with one decision.
class FlowMove {
  const FlowMove({
    required this.step,
    required this.lines,
    required this.listen,
    this.dictate = false,
    this.focusPassword = false,
    this.submit = false,
    this.stop = false,
    this.continueAfter = false,
    this.email,
  });

  final CreateAccountStep step;

  /// Said as one utterance, in order. Empty when there is nothing new to say.
  final List<String> lines;

  /// When true, the runner listens after saying [lines].
  final bool listen;

  /// Email and spelling use the longer dictation window.
  final bool dictate;

  /// Move focus to the password field and open the keyboard.
  final bool focusPassword;

  /// Call the screen's existing create-account handler.
  final bool submit;

  /// Say [lines], then leave the microphone closed.
  final bool stop;

  /// Say [lines], then advance with [FlowCommand.continued].
  final bool continueAfter;

  /// The email address to show in the field, when this move learned one.
  final String? email;
}

const String kReadScreenLine =
    'Step 1 of 7. Create your account. Your email and a password of at '
    'least eight characters. There is an email address field, a password '
    'field, and one button: Create account.';

const String kAskEmailLine = 'Now, say your email address.';

const String kSayEmailAgainLine = 'Okay. Say your email address again.';

const String kSpellEmailLine =
    'Okay. Spell your email, one letter at a time.';

const String kEmailInvalidLine =
    "That doesn't look like a complete email address. Let's try again.";

const String kAskPasswordLine =
    "Your password should be at least eight characters. Please type it "
    "now. Say 'done' when you finish.";

const String kAskProceedLine =
    "Would you like to proceed to creating your account? Say "
    "'Create account.'";

const String kMissedLine = "I didn't catch that. Please say it again.";

const String kGiveUpLine =
    'You can tap the microphone button on screen, or type into the field.';

const String kCreatingAccountLine = 'Creating your account. Please wait.';

/// How many times one prompt may be missed before the flow suggests typing.
const int kVoiceFlowTries = 3;

/// Step 1 of 7. One state per prompt.
class CreateAccountFlow {
  CreateAccountStep step = CreateAccountStep.readScreen;
  int misses = 0;
  String email = '';

  FlowMove openingMove() => const FlowMove(
        step: CreateAccountStep.readScreen,
        lines: [kReadScreenLine],
        listen: false,
        continueAfter: true,
      );

  String promptFor(CreateAccountStep id) => switch (id) {
        CreateAccountStep.readScreen => kReadScreenLine,
        CreateAccountStep.askEmail => kAskEmailLine,
        CreateAccountStep.confirmEmail =>
          'I heard: ${spokenEmailAloud(email)}. Keep it, say it again, or '
              'spell it?',
        CreateAccountStep.spellEmail => kSpellEmailLine,
        CreateAccountStep.askPassword => kAskPasswordLine,
        CreateAccountStep.askProceed => kAskProceedLine,
      };

  /// Where to return after the existing create-account handler reports
  /// [message]. The handler has already spoken it.
  FlowMove afterFailure(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('password')) {
      return _go(CreateAccountStep.askPassword);
    }
    if (lower.contains('email') || lower.contains('address')) {
      return _go(CreateAccountStep.askEmail);
    }
    return _go(CreateAccountStep.askProceed);
  }

  FlowMove advance(
    FlowCommand command, {
    String heard = '',
    int passwordLength = 0,
  }) {
    switch (command) {
      case FlowCommand.repeat:
        return _go(step, resetMisses: false);
      case FlowCommand.goBack:
        return _back();
      case FlowCommand.createAccount:
        return FlowMove(step: step, lines: const [], listen: false, submit: true);
      case FlowCommand.changeEmail:
      case FlowCommand.sayEmail:
        return _go(CreateAccountStep.askEmail);
      case FlowCommand.changePassword:
        return _go(CreateAccountStep.askPassword);
      case FlowCommand.fillIn:
        return _fillIn();
      case FlowCommand.again:
        return _again();
      case FlowCommand.spell:
        return _spell();
      case FlowCommand.keep:
        return _keep();
      case FlowCommand.done:
        return _done(passwordLength);
      case FlowCommand.heard:
        return _heard(heard);
      case FlowCommand.continued:
        if (step == CreateAccountStep.readScreen) {
          return _go(CreateAccountStep.askEmail);
        }
        return _go(step, resetMisses: false);
      case FlowCommand.silence:
      case FlowCommand.unclear:
        return _miss();
    }
  }

  FlowMove _fillIn() {
    switch (step) {
      case CreateAccountStep.readScreen:
      case CreateAccountStep.askEmail:
      case CreateAccountStep.confirmEmail:
      case CreateAccountStep.spellEmail:
        return _go(CreateAccountStep.askEmail);
      case CreateAccountStep.askPassword:
      case CreateAccountStep.askProceed:
        return _go(step, resetMisses: false);
    }
  }

  FlowMove _again() {
    switch (step) {
      case CreateAccountStep.askEmail:
      case CreateAccountStep.confirmEmail:
      case CreateAccountStep.spellEmail:
        return _go(
          CreateAccountStep.askEmail,
          preface: const [kSayEmailAgainLine],
        );
      case CreateAccountStep.readScreen:
      case CreateAccountStep.askPassword:
      case CreateAccountStep.askProceed:
        return _go(step, resetMisses: false);
    }
  }

  FlowMove _spell() {
    switch (step) {
      case CreateAccountStep.askEmail:
      case CreateAccountStep.confirmEmail:
      case CreateAccountStep.spellEmail:
        return _go(CreateAccountStep.spellEmail);
      case CreateAccountStep.readScreen:
      case CreateAccountStep.askPassword:
      case CreateAccountStep.askProceed:
        return _miss();
    }
  }

  FlowMove _keep() {
    if (step != CreateAccountStep.confirmEmail) return _miss();
    if (emailAddressProblem(email) != null) {
      return _go(
        CreateAccountStep.askEmail,
        preface: const [kEmailInvalidLine],
      );
    }
    return _go(CreateAccountStep.askPassword);
  }

  FlowMove _done(int passwordLength) {
    if (step != CreateAccountStep.askPassword) return _miss();
    if (passwordLength < 8) {
      return _go(
        CreateAccountStep.askPassword,
        preface: [
          'That is only $passwordLength characters. It needs at least eight. '
              'Please type it again.',
        ],
      );
    }
    return _go(
      CreateAccountStep.askProceed,
      preface: ['I see you typed $passwordLength characters.'],
    );
  }

  FlowMove _heard(String heard) {
    if (step != CreateAccountStep.askEmail &&
        step != CreateAccountStep.spellEmail) {
      return _miss();
    }
    final parsed = spokenEmail(heard);
    if (parsed.isEmpty) return _miss();
    email = parsed;
    return _go(CreateAccountStep.confirmEmail, email: parsed);
  }

  FlowMove _back() {
    switch (step) {
      case CreateAccountStep.spellEmail:
        return _go(CreateAccountStep.confirmEmail);
      case CreateAccountStep.confirmEmail:
        return _go(CreateAccountStep.askEmail);
      case CreateAccountStep.askPassword:
        return _go(CreateAccountStep.confirmEmail);
      case CreateAccountStep.askProceed:
        return _go(CreateAccountStep.askPassword);
      case CreateAccountStep.readScreen:
      case CreateAccountStep.askEmail:
        return _go(CreateAccountStep.askEmail);
    }
  }

  FlowMove _miss() {
    misses += 1;
    final prompt = promptFor(step);
    final focusing = step == CreateAccountStep.askPassword;
    final dictating = step == CreateAccountStep.askEmail ||
        step == CreateAccountStep.spellEmail;
    if (misses >= kVoiceFlowTries) {
      return FlowMove(
        step: step,
        lines: [kMissedLine, kGiveUpLine, prompt],
        listen: false,
        stop: true,
        focusPassword: focusing,
      );
    }
    return FlowMove(
      step: step,
      lines: [kMissedLine, prompt],
      listen: true,
      dictate: dictating,
      focusPassword: focusing,
    );
  }

  FlowMove _go(
    CreateAccountStep next, {
    List<String> preface = const [],
    String? email,
    bool resetMisses = true,
  }) {
    if (resetMisses) misses = 0;
    step = next;
    final prompt = promptFor(next);
    return FlowMove(
      step: next,
      lines: [
        ...preface,
        if (preface.isEmpty || preface.last != prompt) prompt,
      ],
      listen: true,
      dictate: next == CreateAccountStep.askEmail ||
          next == CreateAccountStep.spellEmail,
      focusPassword: next == CreateAccountStep.askPassword,
      email: email,
    );
  }
}

/// The reply [heard] is, for [step]. Nothing in the result carries the
/// words themselves: a password said by mistake is not kept on the command.
FlowCommand interpretAccountReply(CreateAccountStep step, String? heard) {
  if (heard == null) return FlowCommand.silence;
  var said = heard
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  while (said.isNotEmpty) {
    final stripped = said.replaceFirst(RegExp(r'\s+(please|po)$'), '');
    if (stripped == said) break;
    said = stripped.trim();
  }
  if (said.isEmpty) return FlowCommand.silence;

  if (said == 'say it again') return FlowCommand.again;
  if (const {
    'repeat',
    'say that again',
    'again',
    'ulit',
    'ulitin',
    'pakiulit',
  }.contains(said)) {
    return FlowCommand.repeat;
  }
  if (said == 'go back' || said == 'back') return FlowCommand.goBack;
  if (said == 'create account') return FlowCommand.createAccount;
  if (said == 'change my email') return FlowCommand.changeEmail;
  if (said == 'change my password') return FlowCommand.changePassword;
  if (said == 'say the email address') return FlowCommand.sayEmail;
  if (said == 'fill in') return FlowCommand.fillIn;
  if (said == 'listening for commands' || said == 'tap to speak') {
    return FlowCommand.repeat;
  }

  final spelling = step == CreateAccountStep.askEmail ||
      step == CreateAccountStep.confirmEmail ||
      step == CreateAccountStep.spellEmail;
  if (spelling && _isSpell(said)) return FlowCommand.spell;

  if (step == CreateAccountStep.confirmEmail) {
    final edit = parseDictationEdit(heard);
    if (edit is EditDone) return FlowCommand.keep;
    if (edit is EditSpell) return FlowCommand.spell;
    if (edit is EditRetry) return FlowCommand.again;
    if (edit is EditReadBack) return FlowCommand.repeat;
    return FlowCommand.unclear;
  }

  if (step == CreateAccountStep.askPassword) {
    if (said == 'done') return FlowCommand.done;
    return FlowCommand.unclear;
  }

  if (step == CreateAccountStep.askEmail ||
      step == CreateAccountStep.spellEmail) {
    return FlowCommand.heard;
  }

  return FlowCommand.unclear;
}

bool _isSpell(String said) => const {
      'spell',
      'spell it',
      'let me spell it',
      'letter by letter',
    }.contains(said);
