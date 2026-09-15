import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/voice_commands.dart';

ParsedCommand? parse(String words, [Set<VoiceCommand>? only]) =>
    parseVoiceCommand(words, only: only ?? VoiceCommand.values.toSet());

void main() {
  group('commands that carry a place or a name', () {
    test('"take me to" and its variants take the place after them', () {
      for (final (said, place) in [
        ('take me to the clinic', 'the clinic'),
        ('navigate to Jollibee Malolos', 'jollibee malolos'),
        ('please take me to SM City please', 'sm city'),
        ('dalhin ako sa palengke', 'palengke'),
        ('pumunta sa simbahan po', 'simbahan'),
        ('go to home', 'home'),
      ]) {
        final heard = parse(said);
        expect(heard?.command, VoiceCommand.navigateTo, reason: said);
        expect(heard?.argument, place, reason: said);
      }
    });

    test('"hello friend" takes the name after it', () {
      // The tester's own example.
      final heard = parse('Hello friend Sam');
      expect(heard?.command, VoiceCommand.rememberFriend);
      expect(heard?.argument, 'sam');
      expect(parse('this is my friend Ana Reyes')?.argument, 'ana reyes');
      expect(parse('kaibigan ko si Ben')?.argument, 'ben');
      // "hey" is a filler everywhere else; here it starts the trigger.
      expect(parse('hey friend Sam')?.argument, 'sam');
      expect(parse('okay, hello friend Sam')?.argument, 'sam');
      expect(parse('hey, take me home')?.argument, 'home');
    });

    test('"forget" takes the name, and "si" is not part of it', () {
      expect(parse('forget Sam')?.command, VoiceCommand.forgetFriend);
      expect(parse('kalimutan si Sam')?.argument, 'sam');
    });

    test('"take me home" is directions home; "take me back" is not', () {
      expect(parse('take me home')?.command, VoiceCommand.navigateTo);
      expect(parse('take me home')?.argument, 'home');
      expect(parse('bring me home please')?.argument, 'home');
      expect(parse('take me back')?.command, VoiceCommand.back);
    });

    test('a trigger with nothing after it is not the command', () {
      expect(parse('take me to')?.command, isNot(VoiceCommand.navigateTo));
      expect(parse('hello friend')?.command, isNot(VoiceCommand.rememberFriend));
    });

    test('the trigger has to start what was said', () {
      // "I forget where I parked" is not a request to forget anyone.
      expect(parse('I forget where I parked', kScanCommands)?.command,
          isNot(VoiceCommand.forgetFriend));
    });
  });

  group('phrases', () {
    test('the longest phrase wins, so "stop directions" is not "stop"', () {
      expect(parse('stop directions', kScanCommands)?.command,
          VoiceCommand.stopDirections);
      expect(parse('stop', kReadingCommands)?.command, VoiceCommand.pause);
      expect(parse('stop', kCancellationCommands)?.command,
          VoiceCommand.cancel);
    });

    test('Read Text answers to basahin as well as read', () {
      expect(parse('basahin', kReadingCommands)?.command, VoiceCommand.read);
      expect(parse('read this', kReadingCommands)?.command, VoiceCommand.read);
      expect(parse('susunod', kReadingCommands)?.command, VoiceCommand.next);
      expect(parse('ituloy', kReadingCommands)?.command, VoiceCommand.resume);
      expect(parse('say that again', kReadingCommands)?.command,
          VoiceCommand.repeat);
    });

    test("contractions a question hinges on are opened up", () {
      expect(parse("who's there", kScanCommands)?.command,
          VoiceCommand.whoIsHere);
      expect(parse("what's around me")?.command, VoiceCommand.scan);
    });

    test('help still outranks everything else said with it', () {
      expect(parse('take me to the emergency room')?.command, VoiceCommand.help,
          reason: 'documented: a missed emergency is the worse mistake');
      expect(parse('pause help', kReadingCommands)?.command, VoiceCommand.help);
    });
  });

  group('each screen hears only its own words', () {
    test('no vocabulary holds two commands that share a word', () {
      // "stop" is pause on Read Text and cancel on the SOS countdown; a
      // vocabulary holding both could not tell which was meant.
      kScreenVocabularies.forEach((name, commands) {
        final seen = <String, VoiceCommand>{};
        for (final command in commands) {
          for (final phrase in kVoiceKeywords[command]!) {
            final other = seen[phrase];
            expect(other, isNull,
                reason: '$name: "$phrase" is both $other and $command');
            seen[phrase] = command;
          }
        }
      });
    });

    test('the dashboard does not hear reading controls', () {
      expect(parse('pause', kEverydayCommands), isNull);
      expect(parse('next', kEverydayCommands), isNull);
    });

    test('an answer is yes, no, or next', () {
      expect(parse('opo', kAnswerCommands)?.command, VoiceCommand.yes);
      expect(parse('yes please', kAnswerCommands)?.command, VoiceCommand.yes);
      expect(parse('hindi', kAnswerCommands)?.command, VoiceCommand.no);
      expect(parse('next one', kAnswerCommands)?.command, VoiceCommand.next);
    });
  });

  test('every argument command says what goes after it', () {
    for (final command in kArgumentCommands) {
      expect(kArgumentHints[command], isNotEmpty, reason: '$command');
    }
  });
}
