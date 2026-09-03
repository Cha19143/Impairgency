import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/safety/safety_notice.dart';

void main() {
  group('the §7 limitation notice', () {
    test('says something, and says it in more than one line', () {
      expect(kSafetyNotice.headline, isNotEmpty);
      expect(kSafetyNotice.lines.length, greaterThanOrEqualTo(3));
    });

    test('every line is short enough to follow by ear', () {
      // A line a screen reader user misses has to be replayed in full, so the
      // unit of replay is kept small.
      for (final line in kSafetyNotice.lines) {
        expect(line.length, lessThanOrEqualTo(130),
            reason: 'too long to hold in one listen: "$line"');
      }
    });

    test('every line is a finished sentence', () {
      for (final line in kSafetyNotice.lines) {
        expect(line.trim(), endsWith('.'), reason: line);
      }
    });

    test('names concrete failures rather than hedging', () {
      final text = kSafetyNotice.spoken.toLowerCase();
      // §7 asks the app not to guarantee safety. "Results may vary" satisfies a
      // lawyer and tells a blind user nothing they can act on.
      expect(text, contains('will not always be right'));
      expect(
        ['step', 'branch', 'car'].where(text.contains).length,
        greaterThanOrEqualTo(2),
        reason: 'should name specific things it misses',
      );
    });

    test('tells the user what to keep doing', () {
      final text = kSafetyNotice.spoken.toLowerCase();
      expect(text, contains('cane'));
      expect(text, anyOf(contains('judgement'), contains('judgment')));
    });

    test('never claims the environment is safe', () {
      final text = kSafetyNotice.spoken.toLowerCase();
      for (final claim in ['guarantee', 'ensures your safety', 'keeps you safe',
        'completely safe']) {
        expect(text, isNot(contains(claim)), reason: 'claims too much: $claim');
      }
    });

    test('the spoken form joins headline and lines', () {
      expect(kSafetyNotice.spoken, startsWith(kSafetyNotice.headline));
      for (final line in kSafetyNotice.lines) {
        expect(kSafetyNotice.spoken, contains(line));
      }
    });
  });
}
