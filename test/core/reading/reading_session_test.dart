import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/reading/reading_session.dart';

void main() {
  group('cutting a page into pieces', () {
    test('lines first, then sentences within a line', () {
      expect(
        splitIntoChunks('PARACETAMOL 500mg\nTake one tablet. Do not exceed '
            'eight in 24 hours!\n\nKeep out of reach of children.'),
        [
          'PARACETAMOL 500mg',
          'Take one tablet.',
          'Do not exceed eight in 24 hours!',
          'Keep out of reach of children.',
        ],
      );
    });

    test('drops blanks and stray punctuation', () {
      expect(splitIntoChunks('  \n...\n- \nHello.\n'), ['Hello.']);
      expect(splitIntoChunks(''), isEmpty);
    });
  });

  group('keeping the place', () {
    test('reads forward, and knows when it is done', () {
      final s = ReadingSession('One.\nTwo.\nThree.');
      expect(s.state, ReadingState.reading);
      expect(s.current, 'One.');
      expect(s.progress, 'Line 1 of 3');
      expect(s.advance(), 'Two.');
      expect(s.advance(), 'Three.');
      expect(s.advance(), isNull);
      expect(s.state, ReadingState.finished);
    });

    test('pause keeps the piece, resume continues from it', () {
      final s = ReadingSession('One.\nTwo.');
      s.advance();
      s.pause();
      expect(s.state, ReadingState.paused);
      expect(s.current, 'Two.');
      s.resume();
      expect(s.state, ReadingState.reading);
      expect(s.current, 'Two.');
    });

    test('back means the line the listener missed', () {
      final s = ReadingSession('One.\nTwo.');
      s.advance();
      expect(s.back(), 'One.');
      expect(s.back(), 'One.', reason: 'cannot go before the start');
    });

    test('an empty page is empty, not finished', () {
      final s = ReadingSession('   ');
      expect(s.isEmpty, isTrue);
      expect(s.state, ReadingState.empty);
      expect(s.progress, 'Nothing to read');
    });

    test('restart goes to the top', () {
      final s = ReadingSession('One.\nTwo.');
      s.advance();
      s.pause();
      s.restart();
      expect(s.current, 'One.');
      expect(s.isPaused, isFalse);
    });
  });
}
