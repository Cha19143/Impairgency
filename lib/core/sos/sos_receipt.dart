/// What an SOS actually did, and how it is said.
///
/// §7 asks emergency features to have fallbacks. The receipt is the fallback
/// for the fallbacks: when a leg fails there is nothing left to do except tell
/// the user, truthfully, so they can try something else.
///
/// The rule this file exists to enforce: **the app never implies success it did
/// not have.** A receipt that says "help is on the way" when nothing was
/// delivered is worse than no receipt, because the user stops trying.
library;

/// The independent things an SOS attempts, in order of what they need.
///
/// Ordered deliberately: the first two work with no account, no network and no
/// guardian, so they are attempted first and never gated on anything else.
enum SosLeg {
  /// The phone makes a noise. Needs nothing but a speaker.
  alarm,

  /// Rings the emergency contact. Needs a saved contact and cell signal — but
  /// no data connection, which is why it outranks anything push-based.
  call,

  /// Attaches a position to the event.
  location,

  /// Tells the paired guardians.
  guardians,
}

enum LegOutcome {
  done,

  /// Attempted and did not work.
  failed,

  /// Nothing to attempt: no contact saved, no guardian paired, consent off.
  /// Distinct from [failed] because the remedy is different and the user
  /// should hear which it was.
  notConfigured,

  /// Attempted, and not confirmed either way: the alert is queued on the
  /// phone for a connection that is not there. Not a success - nobody has
  /// been reached - and not a failure - it will go when the network returns.
  /// Saying which is the difference between a user who waits and one who
  /// gives up.
  pending,

  /// Not attempted, because the user said cancel first - after the countdown,
  /// while the alarm sounded and the position was found, before anyone was
  /// called.
  cancelled,
}

class LegResult {
  const LegResult(this.leg, this.outcome, {this.detail});

  final SosLeg leg;
  final LegOutcome outcome;

  /// Already-written prose, such as the sentence from `resolveLocationForSos`.
  final String? detail;

  bool get succeeded => outcome == LegOutcome.done;
}

class SosReceipt {
  const SosReceipt(this.legs, {this.eventId});

  final List<LegResult> legs;

  /// The record written for this SOS, so it can be marked resolved. Null
  /// when nothing was written: nobody signed in, or cancelled first.
  final String? eventId;

  LegResult? of(SosLeg leg) =>
      legs.where((l) => l.leg == leg).firstOrNull;

  /// Every call, in the order they were placed. More than one when the
  /// user rang the next contact from the receipt.
  List<LegResult> get calls => legs.where((l) => l.leg == SosLeg.call).toList();

  /// The user stopped it before the call.
  bool get cancelled => legs.any((l) => l.outcome == LegOutcome.cancelled);

  bool get anyoneReached =>
      calls.any((c) => c.succeeded) ||
      (of(SosLeg.guardians)?.succeeded ?? false);

  /// The receipt with one more call on it, kept in reading order.
  SosReceipt withCall(LegResult call) {
    final index = legs.lastIndexWhere((l) => l.leg == SosLeg.call);
    final next = [...legs];
    next.insert(index < 0 ? 1 : index + 1, call);
    return SosReceipt(next, eventId: eventId);
  }

  bool get everythingWorked => legs.every((l) => l.succeeded);

  /// The spoken receipt.
  ///
  /// Leads with whether a person was reached, because that is the only thing
  /// the user needs in the first two seconds. Everything else follows.
  String get spoken {
    final lines = <String>[
      if (cancelled)
        'Cancelled before calling.'
      else if (anyoneReached)
        _whoWasReached()
      else
        'Nobody was reached.',
      for (final leg in legs) sentenceFor(leg),
    ];
    return lines.join(' ');
  }

  String _whoWasReached() {
    final called = calls.any((c) => c.succeeded);
    final guardians = of(SosLeg.guardians)?.succeeded ?? false;
    if (called && guardians) return 'Your contact answered and your guardian was told.';
    if (called) return 'Your contact answered.';
    return 'Your guardian was told.';
  }

  /// One leg, in the same words the receipt speaks.
  ///
  /// Public so the screen renders exactly what is said. Two copies of this
  /// wording would eventually disagree, and the one a user hears and the one
  /// they read must not.
  String sentenceFor(LegResult result) => switch ((result.leg, result.outcome)) {
        (SosLeg.alarm, LegOutcome.done) => 'The alarm is sounding.',
        (SosLeg.alarm, _) => 'The alarm did not sound.',

        (SosLeg.call, LegOutcome.done) =>
          result.detail == null ? 'Your contact was called.' : 'Called ${result.detail}.',
        (SosLeg.call, LegOutcome.notConfigured) =>
          'No emergency contact is saved, so nobody was called.',
        (SosLeg.call, LegOutcome.cancelled) =>
          'You said cancel, so nobody was called.',
        (SosLeg.call, _) =>
          result.detail == null
              ? 'The call did not connect.'
              : 'The call to ${result.detail} did not connect.',

        // Already a full sentence from the location policy, which names which
        // of the four failures it was.
        (SosLeg.location, LegOutcome.cancelled) => 'Your location was not sent.',
        (SosLeg.location, _) => result.detail ?? 'Your location was not sent.',

        (SosLeg.guardians, LegOutcome.done) =>
          result.detail == null
              ? 'Your guardian was told.'
              : '${result.detail} were told.',
        (SosLeg.guardians, LegOutcome.notConfigured) =>
          'You have no guardian, so nobody was alerted.',
        (SosLeg.guardians, LegOutcome.cancelled) =>
          'You said cancel, so your guardian was not alerted.',
        (SosLeg.guardians, LegOutcome.pending) =>
          'Your guardian alert is waiting for a connection, and will be sent '
              'as soon as this phone has one.',
        (SosLeg.guardians, _) => result.detail == null
            ? 'Your guardian could not be reached.'
            : 'Your guardian could not be reached. ${result.detail}',
      };

  /// One line for the top of the screen, and the first thing spoken.
  String get headline => cancelled
      ? 'Cancelled before calling'
      : anyoneReached
          ? 'Help has been called'
          : 'Nobody was reached';
}

/// What is said when the user says they are okay after the call, by whether
/// the record could be marked resolved.
String okayAnnouncement(LegOutcome resolved, {required bool hasGuardian}) =>
    switch (resolved) {
      LegOutcome.done when hasGuardian =>
        'Okay. Your guardian will be told you are all right.',
      LegOutcome.pending when hasGuardian =>
        'Okay. Your guardian will be told you are all right as soon as this '
            'phone has a connection.',
      LegOutcome.failed when hasGuardian =>
        'Okay. Your guardian could not be told that you are all right. Call '
            'them if you can.',
      _ => 'Okay. Nothing more will be sent.',
    };
