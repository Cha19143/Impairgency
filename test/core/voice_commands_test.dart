import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/voice_commands.dart';

void main() {
  group('matchVoiceCommand - ported from cprwire, all green', () {
    test('recognizes the three original English commands', () {
      expect(matchVoiceCommand('scan'), VoiceCommand.scan);
      expect(matchVoiceCommand('navigate'), VoiceCommand.navigate);
      expect(matchVoiceCommand('help'), VoiceCommand.help);
    });

    test('recognizes Filipino commands', () {
      expect(matchVoiceCommand('tulong'), VoiceCommand.help);
      expect(matchVoiceCommand('saklolo po'), VoiceCommand.help);
      expect(matchVoiceCommand('gabay'), VoiceCommand.navigate);
      expect(matchVoiceCommand('tingnan mo'), VoiceCommand.scan);
    });

    test('finds the command inside a natural sentence', () {
      expect(matchVoiceCommand('please scan the room'), VoiceCommand.scan);
      expect(matchVoiceCommand('I need help now'), VoiceCommand.help);
      expect(
          matchVoiceCommand('can you navigate for me'), VoiceCommand.navigate);
    });

    test('is case and punctuation insensitive', () {
      expect(matchVoiceCommand('HELP!'), VoiceCommand.help);
      expect(matchVoiceCommand('  Scan, please.  '), VoiceCommand.scan);
    });

    test('emergency outranks any other command in the same phrase', () {
      expect(matchVoiceCommand('scan then help'), VoiceCommand.help);
      expect(matchVoiceCommand('navigate help'), VoiceCommand.help);
    });

    test('accepts the assistance variants', () {
      expect(matchVoiceCommand('assistance'), VoiceCommand.navigate);
      expect(matchVoiceCommand('assist me'), VoiceCommand.navigate);
      expect(matchVoiceCommand('navigation'), VoiceCommand.navigate);
    });

    test('ignores speech with no command in it', () {
      expect(matchVoiceCommand(''), isNull);
      expect(matchVoiceCommand('what time is it'), isNull);
      expect(matchVoiceCommand('hello there'), isNull);
    });

    test('does not fire on words that merely contain a keyword', () {
      expect(matchVoiceCommand('unhelpful'), isNull);
      expect(matchVoiceCommand('discan'), isNull);
      expect(matchVoiceCommand('my back hurts'), isNull);
    });

    test('does not fire on words that merely start with one', () {
      // "That was helpful" used to start an SOS.
      expect(matchVoiceCommand('that was helpful'), isNull);
      expect(matchVoiceCommand('the scanner is broken'), isNull);
      expect(matchVoiceCommand('sosyal media'), isNull);
      expect(matchVoiceCommand('we paired up'), isNull);
    });

    test('hears letters spelled out one at a time', () {
      expect(matchVoiceCommand('S O S'), VoiceCommand.help);
      expect(matchVoiceCommand('s.o.s.'), VoiceCommand.help);
      expect(matchVoiceCommand('where am I'), VoiceCommand.whereAmI,
          reason: 'a lone "I" is still a word');
    });

    test('the inflections worth hearing are listed', () {
      expect(matchVoiceCommand('tulungan ako'), VoiceCommand.help);
      expect(matchVoiceCommand('gabayan mo ako'), VoiceCommand.navigate);
      expect(matchVoiceCommand('start scanning'), VoiceCommand.scan);
    });
  });

  group('the three commands the requirements document asks for (§2.C)', () {
    test('checking the user location', () {
      expect(matchVoiceCommand('where am I'), VoiceCommand.whereAmI);
      expect(matchVoiceCommand('nasaan ako'), VoiceCommand.whereAmI);
      expect(matchVoiceCommand('what is my location'), VoiceCommand.whereAmI);
    });

    test('contacting a guardian', () {
      expect(matchVoiceCommand('call my guardian'), VoiceCommand.callGuardian);
      expect(matchVoiceCommand('tawagan si nanay'), VoiceCommand.callGuardian);
    });

    test('connecting a supported device', () {
      expect(matchVoiceCommand('connect my device'),
          VoiceCommand.connectDevice);
      expect(matchVoiceCommand('pair the device'), VoiceCommand.connectDevice);
    });

    test('all six named functions are reachable', () {
      const spoken = {
        VoiceCommand.scan: 'scan',
        VoiceCommand.navigate: 'navigate',
        VoiceCommand.whereAmI: 'where am I',
        VoiceCommand.callGuardian: 'call my guardian',
        VoiceCommand.help: 'help',
        VoiceCommand.connectDevice: 'connect my device',
      };
      for (final entry in spoken.entries) {
        expect(matchVoiceCommand(entry.value), entry.key,
            reason: '"${entry.value}" should reach ${entry.key}');
      }
    });
  });

  group('cancellation', () {
    test('is not listened for on everyday screens', () {
      // 'hindi' and 'stop' are ordinary words. Hearing them on the dashboard
      // and acting on them would hijack normal speech.
      expect(matchVoiceCommand('hindi ako pupunta'), isNull);
      expect(matchVoiceCommand('stop by the store'), isNull);
    });

    test('works when a screen opts in', () {
      for (final word in ['cancel', 'stop', 'teka', 'tigil', 'sandali',
        'hindi', 'huwag']) {
        expect(matchVoiceCommand(word, only: kCancellationCommands),
            VoiceCommand.cancel,
            reason: '"$word" should cancel');
      }
    });

    test('help still outranks cancel during a countdown', () {
      // Ambiguous phrasing resolves toward summoning help. A false alarm is
      // recoverable; a missed emergency is not.
      expect(matchVoiceCommand('cancel help', only: kCancellationCommands),
          VoiceCommand.help);
    });

    test('an opted-in screen ignores unrelated commands', () {
      expect(matchVoiceCommand('scan', only: kCancellationCommands), isNull);
    });
  });

  group('the vocabulary screen cannot drift from the parser', () {
    test('every command has a description', () {
      for (final command in VoiceCommand.values) {
        expect(kCommandDescriptions[command], isNotNull,
            reason: '$command needs a description for "What can I say?"');
      }
    });

    test('every command has at least one keyword', () {
      for (final command in VoiceCommand.values) {
        expect(kVoiceKeywords[command], isNotEmpty,
            reason: '$command has no way to be said');
      }
    });
  });

  group('round 4: what testers said that did nothing', () {
    test('one letter off a long keyword still counts', () {
      expect(matchVoiceCommand('navigat for me'), VoiceCommand.navigate);
      expect(matchVoiceCommand('asistance'), VoiceCommand.navigate);
    });

    test('asking where a place is asks the way there', () {
      final p = parseVoiceCommand('where is the clinic');
      expect(p?.command, VoiceCommand.navigateTo);
      expect(p?.argument, 'the clinic');
      expect(parseVoiceCommand('saan ang palengke')?.argument, 'palengke');
      expect(parseVoiceCommand('find jollibee')?.argument, 'jollibee');
      expect(matchVoiceCommand('where am i'), VoiceCommand.whereAmI);
      expect(matchVoiceCommand('nasaan ako'), VoiceCommand.whereAmI);
      expect(matchVoiceCommand('where'), isNull, reason: 'where, alone, is nothing');
    });

    test('Tagalog particles do not break a trigger', () {
      final p = parseVoiceCommand('dalhin mo ako sa palengke');
      expect(p?.command, VoiceCommand.navigateTo);
      expect(p?.argument, 'palengke');
      expect(matchVoiceCommand('tulungan mo nga ako'), VoiceCommand.help);
    });

    test('guardian alone is a button, not a call', () {
      expect(matchVoiceCommand('guardian'), isNull);
      expect(matchVoiceCommand('call my guardian'), VoiceCommand.callGuardian);
    });

    test('hands-free on and off, from anywhere', () {
      expect(matchVoiceCommand('turn on hands-free'), VoiceCommand.handsFreeOn);
      expect(matchVoiceCommand('turn off hands free voice'),
          VoiceCommand.handsFreeOff);
      expect(matchVoiceCommand('hands free off please'),
          VoiceCommand.handsFreeOff);
    });

    test('friends, from the home screen', () {
      expect(parseVoiceCommand('hello friend Sam')?.command,
          VoiceCommand.rememberFriend);
      expect(matchVoiceCommand('who is here'), VoiceCommand.whoIsHere);
    });

    test('everyday stop, back and who-is-here are whole phrases', () {
      expect(matchVoiceCommand('stop'), VoiceCommand.cancel);
      expect(matchVoiceCommand('never mind'), VoiceCommand.cancel);
      expect(matchVoiceCommand('go back please'), VoiceCommand.back);
      expect(matchVoiceCommand('take me back'), VoiceCommand.back);
      expect(matchVoiceCommand('my back hurts'), isNull);
      expect(matchVoiceCommand('who is here with me today'), isNull);
    });

    test('I am okay is its own command', () {
      expect(matchVoiceCommand("I'm okay", only: kAfterCallCommands),
          VoiceCommand.allClear);
      expect(matchVoiceCommand('ayos lang po', only: kAfterCallCommands),
          VoiceCommand.allClear);
    });

    test('something that sounds like a command attempt, and chatter', () {
      expect(looksLikeCommandAttempt('navigat for me', allowed: kEverydayCommands),
          isTrue);
      expect(
          looksLikeCommandAttempt('blah blah scan', allowed: kEverydayCommands),
          isTrue);
      expect(
          looksLikeCommandAttempt('did you remember the bread',
              allowed: kEverydayCommands),
          isFalse);
      expect(
          looksLikeCommandAttempt('the weather is nice',
              allowed: kEverydayCommands),
          isFalse);
      expect(
          looksLikeCommandAttempt('saved plases',
              allowed: const {}, labels: ['Saved places']),
          isTrue);
    });
  });
}
