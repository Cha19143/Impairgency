/// When the hands-free microphone opens again, and when it gives up.
///
/// The testers asked not to have to press "Tap to speak". So on the screens
/// where speaking is how the app is used - the dashboard, Scan, Read Text and
/// Smart assistance - the microphone reopens by itself after every phrase. This
/// is the rule for how soon, and for what makes it stop rather than try
/// forever: a microphone that is blocked, or one that keeps failing, is said
/// once and left alone, because a sentence every few seconds about a broken
/// microphone would bury everything else the app says.
///
/// Pure, so the backoff is tested without a microphone or a clock.
library;

/// How one listening window ended.
enum ListenOutcome {
  /// A command was heard and done.
  acted,

  /// Nobody spoke.
  nothingHeard,

  /// Words, but not a command. Background conversation, mostly.
  notUnderstood,

  /// Something else had the microphone - a tap, the SOS countdown.
  busy,

  /// Stopped from outside: a route change, a tap, a hazard warning.
  cancelled,

  /// No permission, or no recogniser on this phone. Asking again will not help.
  blocked,

  /// The recogniser needs a connection and has none.
  network,

  /// Anything else the recogniser reported.
  failed,
}

/// How long a hands-free window stays open, and the silence that ends a
/// phrase in one. Longer than a tap's window, so the microphone restarts - and
/// on some phones beeps - less often.
const Duration kHandsFreeWindow = Duration(seconds: 30);
const Duration kHandsFreePause = Duration(seconds: 3);

/// How long to wait after a hazard warning before listening again.
const Duration kAfterHazard = Duration(milliseconds: 300);

const List<Duration> _networkBackoff = [
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 40),
  Duration(seconds: 60),
];

const List<Duration> _failureBackoff = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
];

/// How long to wait before listening again after [outcome], or null to stop.
///
/// [failuresInARow] counts the failures before this one, of the same kind.
Duration? delayBeforeListening(ListenOutcome outcome,
        {int failuresInARow = 0}) =>
    switch (outcome) {
      ListenOutcome.acted ||
      ListenOutcome.nothingHeard ||
      ListenOutcome.notUnderstood ||
      ListenOutcome.cancelled =>
        const Duration(milliseconds: 250),
      ListenOutcome.busy => const Duration(milliseconds: 500),
      ListenOutcome.blocked => null,
      ListenOutcome.network => _networkBackoff[
          failuresInARow.clamp(0, _networkBackoff.length - 1)],
      ListenOutcome.failed => failuresInARow < _failureBackoff.length
          ? _failureBackoff[failuresInARow]
          : null,
    };

/// Said once when hands-free listening gives up on a failing microphone.
const String kHandsFreeStopped = 'Hands-free listening stopped because the '
    'microphone is not responding. Tap to speak still works.';
