/// Check your email, one prompt at a time.
///
/// The machine decides the next prompt. It does not speak, listen, or call
/// the screen's handlers. The runner does that, and the handlers stay the
/// ones the buttons already use.
///
/// Three misses, the same count as kDictationTries. This file stays free of
/// Flutter, so the count it uses is [kVoiceFlowTries].
library;

import 'screen_flow.dart';
import 'spoken_email.dart';
import 'yes_no.dart';

/// Where Check your email is in its voice flow.
enum VerifyEmailStep { askAction, confirmSignOut, done }

/// What the person said, with the words already interpreted.
enum VerifyEmailCommand {
  silence,
  unclear,
  repeat,
  goBack,
  confirmed,
  resend,
  differentEmail,
  yes,
  no,
}

/// What the runner does with one decision.
class VerifyEmailMove {
  const VerifyEmailMove({
    required this.step,
    required this.lines,
    required this.listen,
    this.check = false,
    this.resend = false,
    this.signOut = false,
    this.stop = false,
  });

  final VerifyEmailStep step;

  /// Said as one utterance, in order. Empty when there is nothing new to say.
  final List<String> lines;

  /// When true, the runner listens after saying [lines].
  final bool listen;

  /// Call the screen's existing check handler. It speaks its own result.
  final bool check;

  /// Call the screen's existing resend handler. It speaks its own result.
  final bool resend;

  /// Call the screen's existing different-email callback.
  final bool signOut;

  /// Say [lines], then leave the microphone closed.
  final bool stop;
}

/// Said once the check handler has already said the address is not confirmed,
/// or that the check failed.
const String kAfterCheckLine =
    "You can say 'I have confirmed my email' again after you open the "
    "link, or say 'Send the link again'.";

/// Said after the resend handler has already said a new link is on its way.
const String kOpenItLine =
    "Open it, then say 'I have confirmed my email'.";

/// Asked before a spoken sign-out. Touch never hears this.
const String kSignOutLine =
    'Using a different email signs you out of this account. Do you want '
    'to continue? Say yes or no.';

/// Said with [kMissedLine] when one question has been missed three times.
/// Step 1 keeps its own wording.
const String kTapAButtonLine =
    'You can tap the microphone button on screen, or tap a button.';

const Set<String> _confirmedPhrases = {
  'i have confirmed my email',
  'confirmed',
  'i confirmed my email',
  'i already confirmed my email',
};

const Set<String> _resendPhrases = {
  'send the link again',
  'send me the link',
  'resend',
};

const Set<String> _differentEmailPhrases = {
  'use a different email',
};

const Set<String> _repeatPhrases = {
  'repeat',
  'say that again',
  'again',
  'ulit',
  'ulitin',
  'pakiulit',
  'listening for commands',
  'tap to speak',
};

/// [email] as it should be said. No address on the account is said as
/// "your email address", not as a blank.
String spokenVerifyAddress(String? email) {
  final trimmed = email?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'your email address';
  return spokenEmailAloud(trimmed);
}

/// The reply [heard] is, for [step].
VerifyEmailCommand interpretVerifyEmailReply(
  VerifyEmailStep step,
  String? heard,
) {
  final said = normalizeUtterance(heard);
  if (said == null) return VerifyEmailCommand.silence;
  if (_repeatPhrases.contains(said)) return VerifyEmailCommand.repeat;
  if (said == 'go back' || said == 'back') return VerifyEmailCommand.goBack;

  if (step == VerifyEmailStep.confirmSignOut) {
    return switch (parseYesNo(said)) {
      YesNo.yes => VerifyEmailCommand.yes,
      YesNo.no => VerifyEmailCommand.no,
      null => VerifyEmailCommand.unclear,
    };
  }

  if (_confirmedPhrases.contains(said)) return VerifyEmailCommand.confirmed;
  if (_resendPhrases.contains(said)) return VerifyEmailCommand.resend;
  if (_differentEmailPhrases.contains(said)) {
    return VerifyEmailCommand.differentEmail;
  }
  return VerifyEmailCommand.unclear;
}

/// Check your email. One state per prompt.
class VerifyEmailFlow {
  VerifyEmailFlow({this.email, this.linkSent = true});

  /// The address the link went to, or null if the account has none.
  String? email;

  /// Whether a link is known to have left. The second action is named from
  /// this, so a screen that has just sent one updates it before the next ask.
  bool linkSent;

  VerifyEmailStep step = VerifyEmailStep.askAction;
  int misses = 0;

  /// The question a repeat, a miss, or a return to the app says again.
  String currentPrompt = '';

  String get secondAction =>
      linkSent ? 'Send the link again' : 'Send me the link';

  String get askLine =>
      "Say 'I have confirmed my email', '$secondAction', or "
      "'Use a different email'.";

  void sync({String? email, required bool linkSent}) {
    this.email = email;
    this.linkSent = linkSent;
  }

  /// The screen's own opening, with the address said aloud, then the question.
  VerifyEmailMove opening() {
    misses = 0;
    step = VerifyEmailStep.askAction;
    final address = spokenVerifyAddress(email);
    final sent = linkSent
        ? 'We sent a link to $address. Open it to confirm the address is '
            'yours, then come back here.'
        : 'Your account is made. Before you can use it, confirm that '
            '$address is yours: ask for a link below, then open it.';
    currentPrompt = askLine;
    return VerifyEmailMove(
      step: step,
      lines: [
        'Check your email',
        sent,
        'Until then the app cannot be used, so that nobody can make an '
            'account with an address that is not theirs.',
        askLine,
      ],
      listen: true,
    );
  }

  /// The current question, and nothing before it.
  VerifyEmailMove reask() {
    misses = 0;
    if (step == VerifyEmailStep.confirmSignOut) {
      currentPrompt = kSignOutLine;
      return const VerifyEmailMove(
        step: VerifyEmailStep.confirmSignOut,
        lines: [kSignOutLine],
        listen: true,
      );
    }
    if (step == VerifyEmailStep.done) {
      return const VerifyEmailMove(
        step: VerifyEmailStep.done,
        lines: [],
        listen: false,
        stop: true,
      );
    }
    step = VerifyEmailStep.askAction;
    currentPrompt = askLine;
    return VerifyEmailMove(
      step: step,
      lines: [askLine],
      listen: true,
    );
  }

  /// After the check handler. A verified address adds no sentence: the router
  /// is moving on. Anything else adds [kAfterCheckLine] only.
  VerifyEmailMove afterChecked({required bool verified}) {
    if (verified) {
      step = VerifyEmailStep.done;
      currentPrompt = '';
      return const VerifyEmailMove(
        step: VerifyEmailStep.done,
        lines: [],
        listen: false,
        stop: true,
      );
    }
    misses = 0;
    step = VerifyEmailStep.askAction;
    currentPrompt = kAfterCheckLine;
    return const VerifyEmailMove(
      step: VerifyEmailStep.askAction,
      lines: [kAfterCheckLine],
      listen: true,
    );
  }

  /// After the resend handler. [sent] adds [kOpenItLine] and nothing else.
  /// A cooldown or a refusal was already spoken by the handler, so the
  /// question is asked again without that line.
  VerifyEmailMove afterResent({required bool sent}) {
    misses = 0;
    step = VerifyEmailStep.askAction;
    if (sent) {
      currentPrompt = kOpenItLine;
      return const VerifyEmailMove(
        step: VerifyEmailStep.askAction,
        lines: [kOpenItLine],
        listen: true,
      );
    }
    currentPrompt = askLine;
    return VerifyEmailMove(
      step: step,
      lines: [askLine],
      listen: true,
    );
  }

  VerifyEmailMove advance(VerifyEmailCommand command) {
    switch (command) {
      case VerifyEmailCommand.repeat:
        return _listen(step, [currentPrompt], resetMisses: false);
      case VerifyEmailCommand.goBack:
        return _back();
      case VerifyEmailCommand.confirmed:
        return const VerifyEmailMove(
          step: VerifyEmailStep.askAction,
          lines: [],
          listen: false,
          check: true,
        );
      case VerifyEmailCommand.resend:
        return const VerifyEmailMove(
          step: VerifyEmailStep.askAction,
          lines: [],
          listen: false,
          resend: true,
        );
      case VerifyEmailCommand.differentEmail:
        return _listen(VerifyEmailStep.confirmSignOut, [kSignOutLine]);
      case VerifyEmailCommand.yes:
        if (step != VerifyEmailStep.confirmSignOut) return _miss();
        step = VerifyEmailStep.done;
        return const VerifyEmailMove(
          step: VerifyEmailStep.done,
          lines: [],
          listen: false,
          signOut: true,
        );
      case VerifyEmailCommand.no:
        if (step != VerifyEmailStep.confirmSignOut) return _miss();
        return _listen(VerifyEmailStep.askAction, [askLine]);
      case VerifyEmailCommand.silence:
      case VerifyEmailCommand.unclear:
        return _miss();
    }
  }

  VerifyEmailMove _back() {
    if (step == VerifyEmailStep.confirmSignOut) {
      return _listen(VerifyEmailStep.askAction, [askLine]);
    }
    return _listen(VerifyEmailStep.askAction, [askLine]);
  }

  VerifyEmailMove _miss() {
    misses += 1;
    final prompt = currentPrompt.isEmpty ? askLine : currentPrompt;
    if (misses >= kVoiceFlowTries) {
      return VerifyEmailMove(
        step: step,
        lines: [kMissedLine, kTapAButtonLine, prompt],
        listen: false,
        stop: true,
      );
    }
    return _listen(step, [kMissedLine, prompt], resetMisses: false);
  }

  VerifyEmailMove _listen(
    VerifyEmailStep next,
    List<String> lines, {
    bool resetMisses = true,
  }) {
    if (resetMisses) misses = 0;
    step = next;
    if (lines.isNotEmpty) currentPrompt = lines.last;
    return VerifyEmailMove(step: next, lines: lines, listen: true);
  }
}
