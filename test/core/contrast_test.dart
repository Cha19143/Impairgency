import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/a11y/contrast.dart';

void main() {
  group('contrast (requirements §4: "maintain high contrast")', () {
    test('every rendered pair clears WCAG AA for body text', () {
      kContrastPairs.forEach((name, pair) {
        final ratio = contrastRatio(pair.$1, pair.$2);
        expect(ratio, greaterThanOrEqualTo(kAaNormalText),
            reason: '$name is ${ratio.toStringAsFixed(2)}:1, '
                'needs $kAaNormalText:1');
      });
    });

    test('the three big action buttons clear AAA', () {
      // These are the controls a blind or partially sighted user is aiming at.
      // AA is the floor for text; for these, AA is not enough.
      for (final name in const [
        'label on primary action',
        'label on secondary action',
        'label on raised surface',
      ]) {
        final pair = kContrastPairs[name]!;
        final ratio = contrastRatio(pair.$1, pair.$2);
        expect(ratio, greaterThanOrEqualTo(kAaaNormalText),
            reason: '$name is ${ratio.toStringAsFixed(2)}:1, '
                'needs $kAaaNormalText:1');
      }
    });

    test('the defect carried over from the old app would fail here', () {
      // cprwire painted button labels with `secondaryBackground`, which is
      // #FFFFFF in the light theme. This is that pairing.
      const whiteOnCyan = 0xFFFFFFFF;
      const cyan = 0xFF00FFFF;
      expect(contrastRatio(whiteOnCyan, cyan), lessThan(kAaLargeText),
          reason: 'white on cyan should be recognised as unreadable');
    });

    test('luminance maths matches the WCAG reference values', () {
      expect(contrastRatio(0xFF000000, 0xFFFFFFFF), closeTo(21.0, 0.01));
      expect(contrastRatio(0xFF808080, 0xFF808080), closeTo(1.0, 0.001));
    });
  });
}
