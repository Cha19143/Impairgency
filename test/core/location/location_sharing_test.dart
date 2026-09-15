import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_sharing.dart';

/// Which readings reach a guardian. The policy is what keeps "Share where I
/// am" from being a write every half minute for someone sitting still.
void main() {
  final t0 = DateTime.utc(2026, 9, 13, 8);
  LocationFix at(double lat, double lng, DateTime when,
          {double accuracy = 12}) =>
      LocationFix(latitude: lat, longitude: lng, accuracyMetres: accuracy, at: when);

  const policy = SharePolicy();
  final home = at(14.5995, 120.9842, t0);

  test('the first reading always goes', () {
    expect(policy.shouldPublish(last: null, next: home, now: t0), isTrue);
  });

  test('a reading that has barely moved does not', () {
    // Ten metres of wander, thirty seconds later.
    final wander = at(14.59959, 120.9842, t0.add(const Duration(seconds: 30)));
    expect(metresBetween(home, wander), lessThan(15));
    expect(
      policy.shouldPublish(last: home, next: wander, now: wander.at),
      isFalse,
    );
  });

  test('a real move does', () {
    final moved = at(14.6005, 120.9842, t0.add(const Duration(seconds: 30)));
    expect(metresBetween(home, moved), closeTo(111, 5));
    expect(policy.shouldPublish(last: home, next: moved, now: moved.at), isTrue);
  });

  test('standing still, the heartbeat refreshes the guardian anyway', () {
    final later = at(14.5995, 120.9842, t0.add(const Duration(minutes: 5)));
    expect(policy.shouldPublish(last: home, next: later, now: later.at), isTrue);
    final sooner = at(14.5995, 120.9842, t0.add(const Duration(minutes: 4)));
    expect(
      policy.shouldPublish(last: home, next: sooner, now: sooner.at),
      isFalse,
    );
  });

  test('a cell-tower guess is never sent, first reading or not', () {
    final vague = at(14.5995, 120.9842, t0, accuracy: 1500);
    expect(policy.shouldPublish(last: null, next: vague, now: t0), isFalse);
  });

  test('metresBetween is symmetric and zero at the same point', () {
    expect(metresBetween(home, home), 0);
    final b = at(14.61, 121.0, t0);
    expect(metresBetween(home, b), closeTo(metresBetween(b, home), 1e-6));
  });
}
