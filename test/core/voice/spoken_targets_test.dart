import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/spoken_targets.dart';
import 'package:impairgency/core/voice/voice_commands.dart';

void main() {
  const settings = [
    'Hands-free listening',
    'Change your emergency contact',
    'Saved places',
    'Back',
  ];

  group('a button is named', () {
    test('by its label, however it is capitalised or punctuated', () {
      expect(matchSpokenTargets('saved places', settings), [2]);
      expect(matchSpokenTargets('hands free listening', settings), [0]);
      expect(matchSpokenTargets('EMERGENCY SOS', ['EMERGENCY SOS']), [0]);
    });

    test('with a word to press it in front', () {
      expect(matchSpokenTargets('tap saved places', settings), [2]);
      expect(matchSpokenTargets('press back', settings), [3]);
      expect(matchSpokenTargets('pindutin back', settings), [3]);
    });

    test('without the small words in it', () {
      expect(matchSpokenTargets('change emergency contact', settings), [1]);
    });

    test('in a phrase a little longer than the label', () {
      expect(matchSpokenTargets('please press the back button', settings), [3]);
    });
  });

  group('a button is not named', () {
    test('by a sentence that only happens to contain its word', () {
      // Background talk in hands-free mode must not press Back.
      expect(matchSpokenTargets("I'll be right back after lunch", settings),
          isEmpty);
    });

    test('by part of its label', () {
      expect(matchSpokenTargets('emergency', settings), isEmpty);
    });

    test('by nothing', () {
      expect(matchSpokenTargets('', settings), isEmpty);
    });
  });

  group('two buttons at once', () {
    test('an exact label wins over one that only contains the words', () {
      expect(matchSpokenTargets('save', ['Save', 'Save and continue']), [0]);
      expect(matchSpokenTargets('save and continue',
          ['Save', 'Save and continue']), [1]);
    });

    test('are both returned when the phrase names both, for the app to ask',
        () {
      expect(matchSpokenTargets('remove home', ['Remove Home', 'Home']), [0]);
      expect(
          matchSpokenTargets(
              'call mum', ['Call Mum on her mobile', 'Call Mum at work']),
          isEmpty,
          reason: 'too short to name either');
      expect(matchSpokenTargets('call mum mobile work',
          ['Call Mum mobile', 'Call Mum work']), [0, 1]);
    });
  });

  test('only an exact label, when asked for one', () {
    expect(matchSpokenTargets('please press the back button', settings,
        exactOnly: true), isEmpty);
    expect(matchSpokenTargets('back', settings, exactOnly: true), [3]);
  });

  group('a command said on its own', () {
    test('is the command', () {
      expect(isOnlyCommandPhrase('back', VoiceCommand.back), isTrue);
      expect(isOnlyCommandPhrase('What can I say?', VoiceCommand.whatCanISay),
          isTrue);
    });

    test('but not when it is only a word of something longer', () {
      expect(isOnlyCommandPhrase('share my location', VoiceCommand.whereAmI),
          isFalse);
    });
  });

  group('an answer to "did you mean"', () {
    const choices = ['Call Mum at work', 'Call Mum on her mobile'];

    test('picks by a word only one of them has', () {
      expect(matchChoice('work', choices), [0]);
      expect(matchChoice('the mobile', choices), [1]);
    });

    test('picks by position', () {
      expect(matchChoice('the second one', choices), [1]);
      expect(matchChoice('una', choices), [0]);
    });

    test('picks neither when the answer fits both, or neither', () {
      expect(matchChoice('mum', choices), [0, 1]);
      expect(matchChoice('the bakery', choices), isEmpty);
    });
  });

  group('round 4', () {
    test('a word one letter off still names its button', () {
      expect(matchSpokenTargets('save places', ['Saved places', 'Settings']),
          [0]);
    });

    test('"on" is part of what is said, except after tap', () {
      expect(matchSpokenTargets('tap on back', ['Back', 'Settings']), [0]);
      expect(identifyingWords('turn on hands free'),
          ['turn', 'on', 'hands', 'free']);
      expect(matchSpokenTargets('hands free voice', ['Hands-free voice']), [0]);
    });
  });

  group('choosing by position', () {
    test('first to fifth, by number, and in Filipino', () {
      expect(choiceByNumber('number two', 5), 1);
      expect(choiceByNumber('the second one', 5), 1);
      expect(choiceByNumber('two', 5), 1);
      expect(choiceByNumber('fifth', 5), 4);
      expect(choiceByNumber('ikalawa', 5), 1);
      expect(choiceByNumber('ikalima po', 5), 4);
    });

    test('only when that is all that was said, and there is one', () {
      expect(choiceByNumber('the one near the market', 5), isNull);
      expect(choiceByNumber('fourth', 3), isNull);
      expect(choiceByNumber('jollibee', 3), isNull);
    });

    test('two buttons with one name are told apart by position', () {
      expect(matchChoice('the second', ['Jollibee', 'Jollibee']), [1]);
      expect(matchChoice('number one', ['Jollibee', 'Jollibee']), [0]);
    });
  });
}
