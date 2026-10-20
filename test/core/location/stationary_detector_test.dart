import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/stationary_detector.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 20, 8);
  LocationFix fix(int minutes, {double lat = 14.5, double acc = 10}) =>
      LocationFix(
        latitude: lat,
        longitude: 121,
        accuracyMetres: acc,
        at: t0.add(Duration(minutes: minutes)),
      );

  // Isang reading bawat 5 minuto, hanggang [to].
  bool runTo(StationaryDetector d, int to, {bool atHome = false}) {
    var fired = false;
    for (var m = 0; m <= to; m += 5) {
      fired = d.note(fix(m), atHome: atHome) || fired;
    }
    return fired;
  }

  test('walang alert bago ang 1 oras', () {
    expect(runTo(StationaryDetector(), 55), isFalse);
  });

  test('may alert pagdating ng 1 oras, at isang beses lang', () {
    final d = StationaryDetector();
    expect(runTo(d, 60), isTrue);
    expect(d.note(fix(65)), isFalse);
  });

  test('gumalaw ang user: nagsisimula ulit ang bilang', () {
    final d = StationaryDetector();
    runTo(d, 50);
    var fired = false;
    for (var m = 55; m <= 110; m += 5) {
      fired = d.note(fix(m, lat: 14.51)) || fired; // ~1 km ang layo
    }
    expect(fired, isFalse);
  });

  test('walang alert sa bahay', () {
    expect(runTo(StationaryDetector(), 120, atHome: true), isFalse);
  });

  test('matagal na walang reading: hindi binibilang ang pagitan', () {
    final d = StationaryDetector();
    d.note(fix(0));
    expect(d.note(fix(90)), isFalse); // sarado ang app nang 90 min
  });

  test('mahinang accuracy ay hindi pinapansin', () {
    final d = StationaryDetector();
    expect(d.note(fix(0, acc: 5000)), isFalse);
  });
}