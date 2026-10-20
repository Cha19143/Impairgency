import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/alerts/guardian_alert.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/stationary_detector.dart';
import 'package:impairgency/core/navigation/destination.dart';

void main() {
  final now = DateTime.utc(2026, 10, 20, 12);

  GuardianAlert alert(String kind, {Duration age = Duration.zero}) =>
      GuardianAlert(
        id: kind,
        userId: 'u1',
        kind: kind,
        message: 'stored',
        at: now.subtract(age),
      );

  test('route deviation and a one-hour stay name the person', () {
    expect(
      guardianAlertSentence(alert(kGuardianAlertRouteDeviation), 'Ana'),
      'Ana left the planned route',
    );
    expect(
      guardianAlertSentence(alert(kGuardianAlertStationary), 'Ana'),
      'Ana has been in one place for 1 hour',
    );
    expect(
      guardianAlertSentence(alert('fall'), null),
      'Someone you watch over. stored',
    );
  });

  test('a route deviation alert waits out its cooldown', () {
    final gate = GuardianAlertCooldown(gap: const Duration(minutes: 5));
    expect(gate.admit(now), isTrue);
    expect(gate.admit(now.add(const Duration(minutes: 4))), isFalse);
    expect(gate.admit(now.add(const Duration(minutes: 5))), isTrue);
  });

  test('an old alert is not shown again, and a new one is shown once', () {
    final seen = <String>{};
    expect(
      shouldShowGuardianAlert(
        alert: alert(kGuardianAlertStationary, age: const Duration(hours: 2)),
        now: now,
        alreadyShown: seen,
      ),
      isFalse,
    );
    final fresh = alert(kGuardianAlertRouteDeviation);
    expect(
      shouldShowGuardianAlert(alert: fresh, now: now, alreadyShown: seen),
      isTrue,
    );
    seen.add(fresh.id);
    expect(
      shouldShowGuardianAlert(alert: fresh, now: now, alreadyShown: seen),
      isFalse,
    );
  });

  test('Home matches the saved place, not a point down the street', () {
    final home = Destination(
      id: 'home',
      label: 'Home',
      kind: DestinationKind.home,
      latitude: 14.6,
      longitude: 120.98,
    );
    LocationFix at(double lat) => LocationFix(
      latitude: lat,
      longitude: 120.98,
      accuracyMetres: 8,
      at: now,
    );
    expect(isAtSavedHome(at(14.6), [home]), isTrue);
    expect(isAtSavedHome(at(14.603), [home]), isFalse);
  });
}
