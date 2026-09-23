/// The seconds between pressing SOS and anything happening.
///
/// `ui.pdf` p.12 put Cancel on screen "immediately after… shows that the system
/// is calling Mom" — a cancel button beside a call already in progress.
/// Cancelling something already done is not cancelling.
///
/// So nothing dials until the countdown ends, and the countdown can be stopped
/// by voice as well as by touch, because someone who has already put the phone
/// in their pocket cannot find a button.
library;

/// Long enough to catch an accidental press, short enough not to matter in a
/// real emergency. Three seconds is roughly the time to say "no, cancel".
const Duration kArmingDuration = Duration(seconds: 3);

enum ArmingState {
  /// Counting down. Nothing has happened yet.
  arming,

  /// Cancelled before anything happened.
  cancelled,

  /// The countdown finished; the legs are running.
  fired,
}

/// What the countdown says at each second.
///
/// Counts down aloud, because a silent countdown gives a blind user no idea how
/// long they have left to stop it.
String armingAnnouncement(int secondsLeft, {String? contactName}) {
  if (secondsLeft <= 0) return 'Calling now.';
  final who = contactName == null || contactName.trim().isEmpty
      ? 'for help'
      : contactName.trim();
  return secondsLeft == 1
      ? 'Calling $who in 1.'
      : 'Calling $who in $secondsLeft.';
}

/// Said once when the countdown starts, so the user knows cancelling is
/// possible at all.
///
/// Two sentences, so "cancel" ends one. Said as one sentence - "Say cancel,
/// or touch the screen anywhere, to stop this." - both "cancel" and "stop"
/// had more of the app's sentence after them, so a partial "cancel" or
/// "stop" might still have been the app talking and was not acted on until
/// the phrase ended. By then the three seconds were up.
const List<String> kArmingHintLines = [
  'Say cancel.',
  'Or touch the screen anywhere.',
];

/// [kArmingHintLines] as one line, for the screen reader.
final String kArmingHint = kArmingHintLines.join(' ');

const String kCancelledAnnouncement =
    'Cancelled. Nothing was sent and nobody was called.';
