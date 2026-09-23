/// Command vocabulary and matching.
///
/// Deliberately free of Flutter imports so it can be unit tested without a
/// widget binding. The microphone plumbing that uses this lives in
/// `lib/vi/voice_controller.dart` and `lib/data/stt_speech_recognizer.dart`.
library;

import 'fuzzy.dart';

/// The commands the app understands.
///
/// The first six are the functions the requirements document names in §2.C:
/// asking what is nearby, starting navigation, checking location, contacting a
/// guardian, activating SOS, and connecting to a supported device.
///
/// [cancel] is not one of those six. It exists because SOS arms on a countdown
/// and a countdown you cannot stop by voice is not cancellable by a blind user
/// who has already put the phone in their pocket.
///
/// The rest came from the testers: "only help works" on Scan, "say read, or
/// basahin" on Read Text, "take me to…" before leaving, and "hello friend Sam".
/// Three of them carry an argument - a place or a name - which is taken from
/// the words that follow the trigger.
enum VoiceCommand {
  help,
  cancel,
  repeat,
  scan,
  navigate,
  navigateTo,
  read,
  next,
  pause,
  resume,
  back,
  stopDirections,
  savePlace,
  whereAmI,
  callGuardian,
  connectDevice,
  whatCanISay,
  rememberFriend,
  forgetFriend,
  whoIsHere,
  yes,
  no,

  /// Answer the questions on this screen by voice, one field at a time.
  fillIn,

  /// "I am okay", after an SOS call: the emergency is over, and the
  /// guardian is told so.
  allClear,

  /// Hands-free listening on or off, from any screen.
  handsFreeOn,
  handsFreeOff,

  /// "Who do I know": the friends saved on this phone.
  listFriends,

  /// "Rename Sam to Samuel".
  renameFriend,

  /// "Forget everyone", asked first.
  forgetAllFriends,
}

/// Words and phrases that map to each command.
///
/// Filipino variants are here on purpose - the users this app is for do not all
/// give commands in English, and 'tulong' has to reach SOS as reliably as
/// 'help' does.
///
/// A phrase is matched as whole words in order. For the commands in
/// [kArgumentCommands] each entry is a trigger that must begin what was said,
/// with the argument after it.
///
/// Iteration order breaks ties, and [VoiceCommand.help] is first by design: if
/// someone says 'help' at all, that outranks whatever else was in the phrase.
/// Failing to summon help is fatal; a false alarm is embarrassing.
const Map<VoiceCommand, List<String>> kVoiceKeywords = {
  VoiceCommand.help: [
    'help',
    'emergency',
    'sos',
    'tulong',
    'tulungan',
    'saklolo',
  ],
  VoiceCommand.cancel: [
    'cancel',
    'stop',
    'nevermind',
    'teka',
    'tigil',
    'sandali',
    'hindi',
    'huwag',
    'never mind',
  ],
  // Not one of the six functions either. It exists because someone who missed
  // a spoken warning has no way to see it again - "repeat" is the only route
  // back to information that has already gone past.
  VoiceCommand.repeat: [
    'repeat',
    'again',
    'say that again',
    'ulit',
    'ulitin',
    'pakiulit',
  ],
  VoiceCommand.scan: [
    'scan',
    'scanning',
    'what is around me',
    'what is in front of me',
    'iskan',
    'detect',
    'nearby',
    'tingnan',
    'silipin',
  ],
  VoiceCommand.navigate: [
    'navigate',
    'navigation',
    'assist',
    'assistance',
    'guide',
    'gabay',
    'gabayan',
    'lakad',
  ],
  VoiceCommand.navigateTo: [
    'navigate to',
    'take me to',
    'guide me to',
    'directions to',
    'walk me to',
    'go to',
    // Asking where a place is, is asking the way to it. "Where am I" is
    // another command, and "where" alone is nothing.
    'where is',
    'find',
    'search for',
    'look for',
    'hanapin',
    'hanapin ang',
    'nasaan ang',
    'saan ang',
    'saan ang daan papunta sa',
    'samahan ako sa',
    // "Take me home" - the example the app itself gives. Not "take me back",
    // which is the way to the main screen; see [_notPlaces].
    'take me',
    'bring me',
    'dalhin ako sa',
    'ihatid ako sa',
    'pumunta sa',
  ],
  VoiceCommand.read: ['read', 'read this', 'basahin', 'basa'],
  VoiceCommand.next: ['next', 'next line', 'sunod', 'susunod'],
  VoiceCommand.pause: ['pause', 'stop reading', 'hinto', 'tigil', 'stop'],
  VoiceCommand.resume: ['continue', 'resume', 'keep reading', 'ituloy', 'tuloy'],
  VoiceCommand.back: [
    'back',
    'go back',
    'take me back',
    'home',
    'go home',
    'main screen',
    'go to the main screen',
    'bumalik',
    'balik',
  ],
  VoiceCommand.stopDirections: [
    'stop directions',
    'stop navigation',
    'cancel directions',
    'end directions',
  ],
  VoiceCommand.savePlace: ['save this place', 'save place', 'save it'],
  // Not "where" on its own: "where is the clinic" is the way there.
  VoiceCommand.whereAmI: [
    'where am i',
    'where are we',
    'my location',
    'location',
    'nasaan ako',
    'nasaan tayo',
    'nasaan',
    'saan ako',
    'lokasyon',
  ],
  // Not "guardian" on its own: that is the name of a Settings button, and
  // saying it to press the button started an emergency alert.
  VoiceCommand.callGuardian: [
    'call my guardian',
    'call guardian',
    'call the guardian',
    'alert my guardian',
    'tell my guardian',
    'contact my guardian',
    'call my caregiver',
    'tawagan',
    'bantay',
  ],
  VoiceCommand.connectDevice: ['connect', 'pair', 'device', 'konekta'],
  VoiceCommand.whatCanISay: [
    'what can i say',
    'commands',
    'voice commands',
    'mga utos',
  ],
  VoiceCommand.rememberFriend: [
    'hello friend',
    'hi friend',
    'hey friend',
    'hello my friend',
    'this is my friend',
    'meet my friend',
    'kaibigan ko si',
    'kaibigan',
  ],
  VoiceCommand.forgetFriend: [
    'forget my friend',
    'forget',
    'kalimutan si',
    'kalimutan',
  ],
  VoiceCommand.whoIsHere: [
    'who is here',
    'who is this',
    'who is there',
    'who is that',
    'sino',
  ],
  VoiceCommand.yes: ['yes', 'yeah', 'yep', 'okay', 'ok', 'sure', 'opo', 'oo', 'sige'],
  VoiceCommand.no: ['no', 'nope', 'hindi', 'huwag'],
  VoiceCommand.fillIn: [
    'fill in',
    'fill it in',
    'fill in the form',
    'answer by voice',
    'dictate',
    'punan',
    'sagutan',
  ],
  // "I'm" reaches the parser as "im": the apostrophe goes, and the two
  // single letters left are joined like a spelled-out word.
  VoiceCommand.allClear: [
    'i am okay',
    'im okay',
    'i am ok',
    'im ok',
    'i am fine',
    'im fine',
    'i am all right',
    'im all right',
    'all clear',
    'false alarm',
    'okay na ako',
    'ok na ako',
    'ayos lang',
    'ayos na',
  ],
  // "Hands-free" reaches the parser as "hands free".
  VoiceCommand.handsFreeOn: [
    'turn on hands free',
    'turn on hands free voice',
    'turn hands free on',
    'hands free on',
    'hands free voice on',
    'start hands free',
    'enable hands free',
    'buksan ang hands free',
  ],
  VoiceCommand.listFriends: [
    'who do i know',
    'who are my friends',
    'list my friends',
    'my friends',
    'sino ang kakilala ko',
    'sino ang mga kaibigan ko',
  ],
  VoiceCommand.renameFriend: [
    'rename',
    'change the name of',
    'palitan ang pangalan ni',
  ],
  // Reached through "forget" with everyone after it, as well as said whole.
  VoiceCommand.forgetAllFriends: [
    'forget everyone',
    'forget everybody',
    'forget all my friends',
    'kalimutan lahat',
  ],
  VoiceCommand.handsFreeOff: [
    'turn off hands free',
    'turn off hands free voice',
    'turn hands free off',
    'hands free off',
    'hands free voice off',
    'stop hands free',
    'disable hands free',
    'patayin ang hands free',
  ],
};

/// Commands whose trigger must start the phrase and be followed by what they
/// act on: a place, or a name.
const Set<VoiceCommand> kArgumentCommands = {
  VoiceCommand.navigateTo,
  VoiceCommand.rememberFriend,
  VoiceCommand.forgetFriend,
  VoiceCommand.renameFriend,
};

/// What "forget" can be followed by that is everyone rather than a name.
const Set<String> _everyone = {
  'everyone',
  'everybody',
  'all',
  'all my friends',
  'all of them',
  'lahat',
};

/// What goes after an argument command's trigger, for "What can I say".
const Map<VoiceCommand, String> kArgumentHints = {
  VoiceCommand.navigateTo: 'a place',
  VoiceCommand.rememberFriend: 'their name',
  VoiceCommand.forgetFriend: 'their name',
  VoiceCommand.renameFriend: 'their name, to, and the new name',
};

/// Commands offered on ordinary screens.
///
/// [VoiceCommand.cancel] - which stops the app talking - is here, but only
/// said on its own: 'hindi' is an everyday Filipino word and 'stop' an
/// everyday English one, and heard in the middle of a sentence they are
/// that sentence. See [kWholePhraseCommands].
///
/// Friends are here so "hello friend Sam" works from the home screen: it
/// opens Scan to meet them.
const Set<VoiceCommand> kEverydayCommands = {
  VoiceCommand.help,
  VoiceCommand.cancel,
  VoiceCommand.repeat,
  VoiceCommand.scan,
  VoiceCommand.navigate,
  VoiceCommand.navigateTo,
  VoiceCommand.read,
  VoiceCommand.back,
  VoiceCommand.whereAmI,
  VoiceCommand.callGuardian,
  VoiceCommand.connectDevice,
  VoiceCommand.whatCanISay,
  VoiceCommand.fillIn,
  VoiceCommand.rememberFriend,
  VoiceCommand.forgetFriend,
  VoiceCommand.whoIsHere,
  VoiceCommand.handsFreeOn,
  VoiceCommand.handsFreeOff,
  VoiceCommand.listFriends,
  VoiceCommand.renameFriend,
  VoiceCommand.forgetAllFriends,
};

/// Commands heard only as the whole of what was said, fillers aside. Each
/// is made of words people say all the time - "stop", "back", "who is" - and
/// the microphone is open while they talk.
const Set<VoiceCommand> kWholePhraseCommands = {
  VoiceCommand.cancel,
  VoiceCommand.back,
  VoiceCommand.whoIsHere,
  VoiceCommand.handsFreeOn,
  VoiceCommand.handsFreeOff,
};

/// Only the ways to stop something already in progress.
const Set<VoiceCommand> kCancellationCommands = {
  VoiceCommand.cancel,
  VoiceCommand.help,
};

/// What the SOS receipt listens for, once the call is over: that the user
/// is okay, or that they still need help. "cancel" is heard as okay too -
/// it is what someone who has just been through the countdown will reach
/// for.
const Set<VoiceCommand> kAfterCallCommands = {
  VoiceCommand.allClear,
  VoiceCommand.cancel,
  VoiceCommand.help,
  VoiceCommand.repeat,
};

/// What Scan listens for. "back" is here but leaving asks first: it stops the
/// obstacle warnings.
const Set<VoiceCommand> kScanCommands = {
  VoiceCommand.help,
  VoiceCommand.repeat,
  VoiceCommand.whereAmI,
  VoiceCommand.stopDirections,
  VoiceCommand.navigateTo,
  VoiceCommand.savePlace,
  VoiceCommand.read,
  VoiceCommand.back,
  VoiceCommand.callGuardian,
  VoiceCommand.whatCanISay,
  VoiceCommand.rememberFriend,
  VoiceCommand.forgetFriend,
  VoiceCommand.whoIsHere,
  VoiceCommand.listFriends,
  VoiceCommand.renameFriend,
  VoiceCommand.forgetAllFriends,
};

/// What the journey screen listens for: Scan's words, whose "stop
/// directions" means something there.
const Set<VoiceCommand> kJourneyCommands = kScanCommands;

/// What Read Text listens for: the three reading controls, and a way out.
const Set<VoiceCommand> kReadingCommands = {
  VoiceCommand.help,
  VoiceCommand.read,
  VoiceCommand.pause,
  VoiceCommand.resume,
  VoiceCommand.repeat,
  VoiceCommand.next,
  VoiceCommand.back,
};

/// What Smart assistance listens for. A saved place's name, said on its own,
/// is handled by the screen before any of these.
const Set<VoiceCommand> kAssistCommands = {
  VoiceCommand.help,
  VoiceCommand.navigateTo,
  VoiceCommand.whereAmI,
  VoiceCommand.repeat,
  VoiceCommand.back,
};

/// An answer to a question the app asked: yes, no, or the next choice.
const Set<VoiceCommand> kAnswerCommands = {
  VoiceCommand.yes,
  VoiceCommand.no,
  VoiceCommand.next,
  VoiceCommand.help,
};

/// Every vocabulary a screen uses, named, so a test can check that none of
/// them holds two commands that share a word - "stop" means pause on Read Text
/// and cancel on the SOS countdown, and must never mean both at once.
const Map<String, Set<VoiceCommand>> kScreenVocabularies = {
  'everyday': kEverydayCommands,
  'cancellation': kCancellationCommands,
  'after call': kAfterCallCommands,
  'scan': kScanCommands,
  'journey': kJourneyCommands,
  'reading': kReadingCommands,
  'assist': kAssistCommands,
  'answer': kAnswerCommands,
};

/// A command heard in a phrase, with what it acts on and what was said.
class ParsedCommand {
  const ParsedCommand(this.command, {this.argument, this.heard = ''});

  final VoiceCommand command;

  /// The place or name after an argument command's trigger, as said.
  final String? argument;

  final String heard;

  @override
  String toString() =>
      'ParsedCommand($command${argument == null ? '' : ', "$argument"'})';
}

/// Said before a command without being part of it. Whole phrases, not loose
/// words: "I want to go to the clinic" is going somewhere, and "I forget
/// where I parked" is not a request to forget anyone.
const List<String> _leadingFillers = [
  'i would like to',
  'i want to',
  'i said',
  'can you',
  'could you',
  'would you',
  'please',
  'okay',
  'ok',
  'hey',
  'um',
  'uh',
  'pwede bang',
  'pwede',
  'gusto kong',
  'gusto ko',
  'paki',
];
const Set<String> _trailingFillers = {
  'please',
  'po',
  'naman',
  'now',
  'thanks',
  'thank you',
  'na',
  'salamat',
  'for me',
};

/// Tagalog particles that soften or stress a request without changing it:
/// "dalhin *mo* ako sa palengke", "tulungan *mo nga* ako". Matched past, so a
/// trigger with none of them still starts the phrase.
const Set<String> kParticles = {
  'mo',
  'po',
  'ho',
  'nga',
  'naman',
  'niyo',
  'muna',
  'lang',
};

/// The most words a help phrase may have in a window the app opened by
/// itself. "Help", "help me", "tulong po" - not "I need help finding the
/// settings", heard across the room with hands-free on.
const int kHandsFreeHelpWords = 3;

/// Words that turn a help phrase into its opposite: "I don't need help".
const Set<String> kNegations = {
  'no',
  'not',
  'dont',
  'don',
  'never',
  'hindi',
  'huwag',
  'wag',
  'di',
};

/// Finds the command in a spoken phrase, or null if there isn't one.
///
/// Matching is by whole word. It used to accept any word that *started* with
/// a keyword, which is how 'assistance' reached navigate - and also how
/// "that was helpful" started an SOS. The inflections worth hearing are listed
/// in [kVoiceKeywords] instead, where they can be read and tested.
///
/// Letters spelled out one at a time are joined first, because a recogniser
/// that hears "S O S" writes three words.
///
/// In order: "help" anywhere; then an argument command whose trigger starts
/// the phrase; then the longest phrase found anywhere; then single words.
///
/// Pass [only] to restrict the vocabulary to what the current screen can act
/// on. Defaults to [kEverydayCommands].
///
/// [helpMaxWords] is for windows the app opened by itself: help is then heard
/// only in a phrase of at most that many words, with no negation in it. A tap
/// on the microphone leaves it null - someone who pressed the button and said
/// help meant it.
///
/// [wholePhrase] names commands heard only as all of what was said, fillers
/// and particles aside. Left null it is [kWholePhraseCommands] for the
/// everyday vocabulary - so "my back hurts" is not "back" - and nothing for a
/// vocabulary a screen chose itself.
///
/// A word of five letters or more one edit from a keyword's counts as it
/// ([wordsAlike]), except the first word of a place or name command's
/// trigger, which is how the argument is found.
ParsedCommand? parseVoiceCommand(String transcript,
    {Set<VoiceCommand>? only,
    int? helpMaxWords,
    Set<VoiceCommand>? wholePhrase}) {
  final allowed = only ?? kEverydayCommands;
  final whole =
      wholePhrase ?? (only == null ? kWholePhraseCommands : const {});
  final words = spokenWords(transcript);
  if (words.isEmpty) return null;

  if (allowed.contains(VoiceCommand.help) &&
      kVoiceKeywords[VoiceCommand.help]!.any(words.contains) &&
      (helpMaxWords == null || _shortHelp(words, helpMaxWords))) {
    return ParsedCommand(VoiceCommand.help, heard: transcript);
  }

  // Fillers are only stripped to find where a trigger starts; the argument
  // keeps what was said. Every place a trigger could start is tried, the
  // first first: "hey" is a filler in "hey, take me home" and the start of
  // the trigger in "hey friend Sam".
  var start = 0;
  final starts = [0];
  var stripped = true;
  while (stripped) {
    stripped = false;
    for (final filler in _leadingFillers) {
      final f = filler.split(' ');
      if (words.length - start > f.length &&
          _startsWith(words.sublist(start), f)) {
        start += f.length;
        starts.add(start);
        stripped = true;
        break;
      }
    }
  }
  var end = words.length;
  while (end > start && _trailingFillers.contains(words[end - 1])) {
    end--;
  }

  // With the particles out, for the triggers - "dalhin mo ako sa" is
  // "dalhin ako sa" - and for the whole phrase.
  final plainCore = [
    for (final w in words.sublist(start, end))
      if (!kParticles.contains(w)) w,
  ];

  for (final core in [
    for (final at in starts) words.sublist(at, end),
    if (plainCore.length != end - start) plainCore,
  ]) {
    for (final command in kArgumentCommands) {
      if (!allowed.contains(command)) continue;
      final triggers = [...kVoiceKeywords[command]!]
        ..sort((a, b) => b.split(' ').length.compareTo(a.split(' ').length));
      for (final trigger in triggers) {
        final t = trigger.split(' ');
        if (core.length > t.length && _startsWith(core, t)) {
          final argument = _tidyArgument(core.sublist(t.length).join(' '));
          if (command == VoiceCommand.navigateTo &&
              _notPlaces.contains(argument)) {
            continue;
          }
          if (command == VoiceCommand.forgetFriend &&
              _everyone.contains(argument)) {
            if (!allowed.contains(VoiceCommand.forgetAllFriends)) continue;
            return ParsedCommand(VoiceCommand.forgetAllFriends,
                heard: transcript);
          }
          return ParsedCommand(command, argument: argument, heard: transcript);
        }
      }
    }
  }

  // Longest phrase first, so "stop directions" is not heard as "stop".
  final plain = [
    for (final w in words)
      if (!kParticles.contains(w)) w,
  ];
  ParsedCommand? best;
  var bestLength = 0;
  for (final entry in kVoiceKeywords.entries) {
    final command = entry.key;
    // Help was decided above, with its own rules.
    if (!allowed.contains(command) ||
        kArgumentCommands.contains(command) ||
        command == VoiceCommand.help) {
      continue;
    }
    final onlyWhole = whole.contains(command);
    for (final phrase in entry.value) {
      final p = phrase.split(' ');
      if (p.length <= bestLength) continue;
      final found = onlyWhole
          ? _same(words.sublist(start, end), p) || _same(plainCore, p)
          : _contains(words, p) || _contains(plain, p);
      if (found) {
        best = ParsedCommand(command, heard: transcript);
        bestLength = p.length;
      }
    }
  }
  return best;
}

/// A help phrase short enough, and plain enough, to be a call for help.
bool _shortHelp(List<String> words, int maxWords) {
  if (words.any(kNegations.contains)) return false;
  var start = 0;
  var stripped = true;
  while (stripped) {
    stripped = false;
    for (final filler in _leadingFillers) {
      final f = filler.split(' ');
      if (words.length - start > f.length &&
          _startsWith(words.sublist(start), f)) {
        start += f.length;
        stripped = true;
        break;
      }
    }
  }
  var end = words.length;
  while (end > start + 1 && _trailingFillers.contains(words[end - 1])) {
    end--;
  }
  return end - start <= maxWords;
}

/// [parseVoiceCommand], for callers that only want the command.
VoiceCommand? matchVoiceCommand(String transcript,
        {Set<VoiceCommand>? only, Set<VoiceCommand>? wholePhrase}) =>
    parseVoiceCommand(transcript, only: only, wholePhrase: wholePhrase)
        ?.command;

/// Whether [words] begins with [prefix]. Its first word exactly - that is
/// where a trigger is told from the words before it - the rest alike.
bool _startsWith(List<String> words, List<String> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (i == 0 ? words[i] != prefix[i] : !wordsAlike(words[i], prefix[i])) {
      return false;
    }
  }
  return true;
}

bool _contains(List<String> words, List<String> phrase) {
  for (var i = 0; i + phrase.length <= words.length; i++) {
    var all = true;
    for (var j = 0; j < phrase.length; j++) {
      if (!wordsAlike(words[i + j], phrase[j])) {
        all = false;
        break;
      }
    }
    if (all) return true;
  }
  return false;
}

bool _same(List<String> words, List<String> phrase) =>
    words.length == phrase.length && _contains(words, phrase);

/// Whether [transcript], heard and not understood, looks like someone
/// trying a command rather than talking: a few words, one of them a
/// command's (or nearly), a button's, or "tap".
///
/// Hands-free hears every conversation in the room. Answering each with
/// "I did not understand" would be a sentence every few seconds; answering
/// none left someone who half-said a command with silence and no idea why.
bool looksLikeCommandAttempt(
  String transcript, {
  required Set<VoiceCommand> allowed,
  Iterable<String> labels = const [],
}) {
  final words = spokenWords(transcript);
  if (words.isEmpty || words.length > 4) return false;
  final phrases = [
    for (final command in allowed) ...?kVoiceKeywords[command],
    ...labels.map((l) => spokenWords(l).join(' ')),
  ];
  return words.any((w) =>
      !_notEvidence.contains(w) && w.length >= 3 && nearKeyword(w, phrases) ||
      const {'tap', 'press', 'open', 'pindutin', 'buksan'}.contains(w));
}

/// Words inside command phrases that say nothing about a command on their
/// own: "the" is in "go to the main screen", and in every other sentence.
const Set<String> _notEvidence = {
  'the', 'and', 'for', 'you', 'are', 'what', 'who', 'this', 'that', 'with',
  'ako', 'ang', 'mga', 'turn', 'call', 'take', 'hands', 'free', 'voice',
};

/// What follows "take me" that is not somewhere to walk to - including the
/// "to" of a "take me to" that stopped there.
const Set<String> _notPlaces = {'to', 'back', 'out', 'away', 'out of here'};

/// "the clinic" stays "the clinic"; "si sam" loses the Filipino name marker.
String _tidyArgument(String argument) {
  final words = argument.split(' ');
  while (words.isNotEmpty && const {'si', 'sa', 'kay'}.contains(words.first)) {
    words.removeAt(0);
  }
  return words.join(' ');
}

/// A transcript as lower-case words: punctuation dropped, contractions a
/// command can hinge on opened up ("who's" is "who is"), and runs of single
/// letters ("s o s") joined into one word ("sos").
List<String> spokenWords(String transcript) {
  final raw = transcript
      .toLowerCase()
      .replaceAllMapped(
          RegExp(r"\b(who|what|where|it|that|there)['’]s\b"),
          (m) => '${m[1]} is')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  final words = <String>[];
  var letters = StringBuffer();
  void flushLetters() {
    if (letters.isEmpty) return;
    words.add(letters.toString());
    letters = StringBuffer();
  }

  for (var i = 0; i < raw.length; i++) {
    final word = raw[i];
    final single = word.length == 1 && RegExp('[a-z]').hasMatch(word);
    final neighbourSingle = (i > 0 && _isLetter(raw[i - 1])) ||
        (i + 1 < raw.length && _isLetter(raw[i + 1]));
    if (single && neighbourSingle) {
      letters.write(word);
    } else {
      flushLetters();
      words.add(word);
    }
  }
  flushLetters();
  return words;
}

bool _isLetter(String word) =>
    word.length == 1 && RegExp('[a-z]').hasMatch(word);

/// What each command does, in the user's words rather than the system's.
///
/// This is the source for the "What can I say?" screen, so that the screen can
/// never drift from what the parser actually accepts.
const Map<VoiceCommand, String> kCommandDescriptions = {
  VoiceCommand.help: 'Start emergency SOS',
  VoiceCommand.cancel: 'Stop what is happening now',
  VoiceCommand.repeat: 'Say the last thing again',
  VoiceCommand.scan: 'Describe what is in front of you',
  VoiceCommand.navigate: 'Open smart assistance',
  VoiceCommand.navigateTo: 'Get walking directions to a place',
  VoiceCommand.read: 'Read the text in front of the camera',
  VoiceCommand.next: 'Go to the next line',
  VoiceCommand.pause: 'Pause reading',
  VoiceCommand.resume: 'Carry on reading',
  VoiceCommand.back: 'Go back to the main screen',
  VoiceCommand.stopDirections: 'Stop the directions, keep the warnings',
  VoiceCommand.savePlace: 'Save where you are going as a place',
  VoiceCommand.whereAmI: 'Say where you are',
  VoiceCommand.callGuardian: 'Alert your guardian',
  VoiceCommand.connectDevice: 'Connect a supported device',
  VoiceCommand.whatCanISay: 'Hear what you can say',
  VoiceCommand.rememberFriend: 'Let the app remember a friend, if they agree',
  VoiceCommand.forgetFriend: 'Make the app forget a friend',
  VoiceCommand.whoIsHere: 'Hear who is in front of you',
  VoiceCommand.yes: 'Answer yes',
  VoiceCommand.no: 'Answer no',
  VoiceCommand.fillIn: 'Answer the questions on this screen by voice',
  VoiceCommand.allClear: 'After an emergency call, say you are okay',
  VoiceCommand.handsFreeOn: 'Listen without a tap before each command',
  VoiceCommand.handsFreeOff: 'Only listen after you tap',
  VoiceCommand.listFriends: 'Hear who is saved as a friend',
  VoiceCommand.renameFriend: 'Change a saved friend\'s name',
  VoiceCommand.forgetAllFriends: 'Forget every saved friend, after a yes',
};
