import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/alerts/reachability.dart';

void main() {
  group('what a guardian is told about being reachable (§3.2, §7)', () {
    test('every state says something different', () {
      final said = {
        for (final r in AlertReachability.values)
          r: criticalAlertsUnavailableGuidance(r)
      };
      expect(said.values.toSet().length, AlertReachability.values.length);
    });

    test('the normal case names Do Not Disturb, because that is the gap', () {
      // §3.2 asks for delivery that prioritises emergencies "where supported by
      // the device and operating system". Without an Apple critical-alert
      // entitlement, iOS Do Not Disturb holds the alert. Saying so is the
      // fallback §7 asks for.
      final text = criticalAlertsUnavailableGuidance(AlertReachability.normal);
      expect(text, contains('Do Not Disturb'));
      expect(text, contains('allowed apps'),
          reason: 'it should say what to do, not only what is wrong');
    });

    test('the critical case is the only one that promises silent-mode audio',
        () {
      expect(criticalAlertsUnavailableGuidance(AlertReachability.critical),
          contains('even if your phone is silent'));
      for (final r in [AlertReachability.normal, AlertReachability.denied]) {
        expect(criticalAlertsUnavailableGuidance(r),
            isNot(contains('even if your phone is silent')),
            reason: '$r must not promise what it cannot do');
      }
    });

    test('a refusal says plainly that they will not be told', () {
      final text = criticalAlertsUnavailableGuidance(AlertReachability.denied);
      expect(text, contains('will not be told'));
      expect(text, contains('Settings'));
    });

    test('no state implies an alert is guaranteed to arrive', () {
      for (final r in AlertReachability.values) {
        final text = criticalAlertsUnavailableGuidance(r).toLowerCase();
        expect(text, isNot(contains('always')), reason: '$r');
        expect(text, isNot(contains('guarantee')), reason: '$r');
      }
    });
  });
}
