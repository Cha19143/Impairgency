import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/where_am_i.dart';
import 'package:impairgency/core/navigation/destination.dart';

final now = DateTime.utc(2026, 9, 15, 9);

LocationFix fix({
  double lat = 14.8430,
  double lng = 120.8110,
  double accuracy = 12,
  Duration age = const Duration(seconds: 5),
}) =>
    LocationFix(
        latitude: lat, longitude: lng, accuracyMetres: accuracy, at: now.subtract(age));

const home = Destination(
    id: 'home',
    label: 'Home',
    latitude: 14.8430,
    longitude: 120.8110,
    kind: DestinationKind.home);

// About 150 metres north of home.
const clinic = Destination(
    id: 'c1', label: 'the clinic', latitude: 14.84435, longitude: 120.8110);

void main() {
  test('never says anything was sent', () {
    // The sentence it used to read was the SOS receipt's.
    for (final f in [fix(), fix(age: const Duration(minutes: 20)), fix(accuracy: 900)]) {
      final said = whereAmISentence(fix: f, now: now, places: const [home]);
      expect(said, isNot(contains('sent')));
    }
  });

  test('names the saved place the user is at', () {
    expect(whereAmISentence(fix: fix(), now: now, places: const [home]),
        startsWith('You are at Home'));
  });

  test('says how far from the nearest saved place', () {
    final said = whereAmISentence(
        fix: fix(), now: now, places: const [clinic]);
    expect(said, contains('about 150 metres from the clinic'));
    expect(said, contains('accurate to about 10 metres'));
  });

  test('an old position says how old', () {
    final said = whereAmISentence(
        fix: fix(age: const Duration(minutes: 20)),
        now: now,
        places: const [home]);
    expect(said, startsWith('I could not get a new position'));
    expect(said, contains('20 minutes ago'));
  });

  test('a rough position is called rough, not placed', () {
    final said =
        whereAmISentence(fix: fix(accuracy: 900), now: now, places: const [home]);
    expect(said, contains('rough position'));
    expect(said, isNot(contains('Home')));
  });

  test('with nothing saved nearby, says so rather than guessing', () {
    final said = whereAmISentence(fix: fix(), now: now);
    expect(said, contains('no place you have saved is nearby'));
  });

  group('with the street from the map', () {
    test('names it when no saved place is near', () {
      expect(
          whereAmISentence(
              fix: fix(), now: now, nearby: 'near Rizal Street, Malolos'),
          'You are near Rizal Street, Malolos, accurate to about 10 metres.');
    });

    test('adds it to the distance from a saved place', () {
      expect(
          whereAmISentence(
              fix: fix(),
              now: now,
              places: const [clinic],
              nearby: 'near Rizal Street, Malolos'),
          'You are about 150 metres from the clinic, near Rizal Street, '
          'Malolos, accurate to about 10 metres.');
    });

    test('at a saved place, the place is enough', () {
      expect(
          whereAmISentence(
              fix: fix(),
              now: now,
              places: const [home],
              nearby: 'near Rizal Street, Malolos'),
          isNot(contains('Rizal')));
    });

    test('a rough position is still not given a street', () {
      expect(
          whereAmISentence(
              fix: fix(accuracy: 900),
              now: now,
              nearby: 'near Rizal Street, Malolos'),
          isNot(contains('Rizal')));
    });
  });
}
