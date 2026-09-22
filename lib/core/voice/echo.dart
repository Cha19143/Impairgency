/// The app's own voice, heard back through its own microphone.
///
/// A phone speaker is a few centimetres from the microphone. When the app
/// listens while it is talking - the SOS countdown does, because it has to
/// keep counting - the recogniser transcribes the app as readily as the
/// person holding it. The countdown says "Say cancel, or touch the screen
/// anywhere, to stop this", and a recogniser that hears that sentence hears
/// the word "cancel" in it.
///
/// Pure, so the rule is tested without a speaker or a microphone.
library;

import 'voice_commands.dart';

/// The shortest run of words, in order, that counts as the app's own voice.
///
/// One word alone is never removed: a person saying "cancel" over the top of
/// the countdown has to be heard. Two words in the order the app said them
/// are very unlikely to be the person.
const int kEchoMinRun = 2;

/// [heard] with every run of [kEchoMinRun] or more words that also appears,
/// in the same order, in one of [spoken] taken out.
///
/// It errs towards removing. For a cancel word that is the safe way round: a
/// cancel missed once is said again, or the screen is tapped; a cancel heard
/// in the app's own sentence stops an emergency call nobody meant to stop.
String withoutEcho(String heard, Iterable<String> spoken) {
  final words = spokenWords(heard).map(_normalise).toList();
  if (words.isEmpty) return '';
  final echoed = List<bool>.filled(words.length, false);

  for (final sentence in spoken) {
    final said = spokenWords(sentence).map(_normalise).toList();
    if (said.length < kEchoMinRun) {
      // A sentence of one word, heard back whole, is the app too: the name of
      // a button pressed by voice, said as it is pressed, must not press it
      // again from the next window.
      if (said.isNotEmpty && words.length == 1 && words.single == said.single) {
        echoed[0] = true;
      }
      continue;
    }
    for (var i = 0; i < words.length; i++) {
      for (var j = 0; j < said.length; j++) {
        var run = 0;
        while (i + run < words.length &&
            j + run < said.length &&
            words[i + run] == said[j + run]) {
          run++;
        }
        if (run >= kEchoMinRun) {
          for (var k = i; k < i + run; k++) {
            echoed[k] = true;
          }
        }
      }
    }
  }

  return [
    for (var i = 0; i < words.length; i++)
      if (!echoed[i]) words[i],
  ].join(' ');
}

/// Whether [heard] ends in a word that one of [spoken] carries on from.
///
/// A partial result is a phrase still arriving. When its last word is one the
/// app says with more after it - "cancel" in "Say cancel, or touch the screen"
/// - the next partial may yet make it the app's own sentence, which
/// [withoutEcho] would take out. Acting on the partial first would act on the
/// app. A word the app does not say, or says only at the end of a sentence, is
/// safe to act on before the phrase ends.
bool mayBeEchoStart(String heard, Iterable<String> spoken) {
  final words = spokenWords(heard);
  if (words.isEmpty) return false;
  final last = _normalise(words.last);
  for (final sentence in spoken) {
    final said = spokenWords(sentence).map(_normalise).toList();
    for (var j = 0; j < said.length - 1; j++) {
      if (said[j] == last) return true;
    }
  }
  return false;
}

/// Digits and number words compare equal: the app says "3", a recogniser
/// may write "three", and the other way round.
String _normalise(String word) => _numbers[word] ?? word;

const Map<String, String> _numbers = {
  '0': 'zero',
  '1': 'one',
  '2': 'two',
  '3': 'three',
  '4': 'four',
  '5': 'five',
  '6': 'six',
  '7': 'seven',
  '8': 'eight',
  '9': 'nine',
  '10': 'ten',
};
