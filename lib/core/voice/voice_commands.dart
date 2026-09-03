/// Command vocabulary and matching.
///
/// Deliberately free of Flutter imports so it can be unit tested without a
/// widget binding. The microphone plumbing that uses this lives in
/// `lib/data/voice_listener.dart`.
library;

/// The commands the app understands.
///
/// The first six are the functions the requirements document names in §2.C:
/// asking what is nearby, starting navigation, checking location, contacting a
/// guardian, activating SOS, and connecting to a supported device.
///
/// [cancel] is not one of those six. It exists because SOS arms on a countdown
/// and a countdown you cannot stop by voice is not cancellable by a blind user
/// who has already put the phone in their pocket.
enum VoiceCommand {
  help,
  cancel,
  scan,
  navigate,
  whereAmI,
  callGuardian,
  connectDevice,
}

/// Words that map to each command.
///
/// Filipino variants are here on purpose - the users this app is for do not all
/// give commands in English, and 'tulong' has to reach SOS as reliably as
/// 'help' does.
///
/// Iteration order is precedence order, and [VoiceCommand.help] is first by
/// design: if someone says 'help' at all, that outranks whatever else was in
/// the phrase. Failing to summon help is fatal; a false alarm is embarrassing.
const Map<VoiceCommand, List<String>> kVoiceKeywords = {
  VoiceCommand.help: ['help', 'emergency', 'sos', 'tulong', 'saklolo'],
  VoiceCommand.cancel: [
    'cancel',
    'stop',
    'nevermind',
    'teka',
    'tigil',
    'sandali',
    'hindi',
    'huwag',
  ],
  VoiceCommand.scan: ['scan', 'iskan', 'detect', 'nearby', 'tingnan', 'silipin'],
  VoiceCommand.navigate: [
    'navigate',
    'navigation',
    'assist',
    'assistance',
    'guide',
    'gabay',
    'lakad',
  ],
  VoiceCommand.whereAmI: ['where', 'location', 'nasaan', 'saan', 'lokasyon'],
  VoiceCommand.callGuardian: ['guardian', 'tawagan', 'bantay', 'caregiver'],
  VoiceCommand.connectDevice: ['connect', 'pair', 'device', 'konekta'],
};

/// Commands offered on ordinary screens.
///
/// [VoiceCommand.cancel] is excluded on purpose. 'hindi' is an everyday
/// Filipino word and 'stop' is an everyday English one; listening for them
/// everywhere would hijack normal speech. Screens that can actually be
/// cancelled - the SOS countdown, chiefly - opt in with [only].
const Set<VoiceCommand> kEverydayCommands = {
  VoiceCommand.help,
  VoiceCommand.scan,
  VoiceCommand.navigate,
  VoiceCommand.whereAmI,
  VoiceCommand.callGuardian,
  VoiceCommand.connectDevice,
};

/// Only the ways to stop something already in progress.
const Set<VoiceCommand> kCancellationCommands = {
  VoiceCommand.cancel,
  VoiceCommand.help,
};

/// Finds the command in a spoken phrase, or null if there isn't one.
///
/// Matching is per word rather than a plain substring search, so 'discan' and
/// 'unhelpful' don't trigger anything. A word that *starts* with a keyword does
/// match, which is what lets 'assistance' reach [VoiceCommand.navigate].
///
/// Pass [only] to restrict the vocabulary to what the current screen can act
/// on. Defaults to [kEverydayCommands].
VoiceCommand? matchVoiceCommand(String transcript, {Set<VoiceCommand>? only}) {
  final allowed = only ?? kEverydayCommands;

  final words = transcript
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return null;

  for (final entry in kVoiceKeywords.entries) {
    if (!allowed.contains(entry.key)) continue;
    for (final keyword in entry.value) {
      if (words.any((w) => w == keyword || w.startsWith(keyword))) {
        return entry.key;
      }
    }
  }
  return null;
}

/// What each command does, in the user's words rather than the system's.
///
/// This is the source for the "What can I say?" screen, so that the screen can
/// never drift from what the parser actually accepts.
const Map<VoiceCommand, String> kCommandDescriptions = {
  VoiceCommand.help: 'Start emergency SOS',
  VoiceCommand.cancel: 'Stop what is happening now',
  VoiceCommand.scan: 'Describe what is in front of you',
  VoiceCommand.navigate: 'Start guided navigation',
  VoiceCommand.whereAmI: 'Say where you are',
  VoiceCommand.callGuardian: 'Call your guardian',
  VoiceCommand.connectDevice: 'Connect a supported device',
};
