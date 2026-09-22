import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/navigation/map_services.dart';
import 'package:impairgency/core/navigation/place_search.dart';

import 'map_fixtures.dart' as map;

const home = Destination(
    id: 'home', label: 'Home', latitude: 1, longitude: 2, kind: DestinationKind.home);
const work = Destination(
    id: 'work', label: 'Capitol office', latitude: 1, longitude: 2, kind: DestinationKind.work);
const clinic = Destination(id: 'c1', label: 'Clinic', latitude: 1, longitude: 2);
const market = Destination(id: 'm1', label: 'Public market', latitude: 1, longitude: 2);

const places = [home, work, clinic, market];

void main() {
  test('a label matches ignoring case, punctuation and "the"', () {
    expect(matchSavedPlace('the clinic', places), clinic);
    expect(matchSavedPlace('Public Market!', places), market);
  });

  test('the ready-made three answer to their words, in English and Filipino', () {
    expect(matchSavedPlace('bahay', places), home);
    expect(matchSavedPlace('my house', places), home);
    expect(matchSavedPlace('trabaho', places), work);
    expect(matchSavedPlace('work', places), work,
        reason: 'even when saved under another label');
  });

  test('a place inside a longer phrase is found when only one fits', () {
    expect(matchSavedPlace('clinic near the church', places), clinic);
  });

  test('a name said on its own is only ever a whole name', () {
    // Smart assistance hears a bare name as the answer to "where are you
    // going?" - and hears everything else too.
    expect(savedPlaceNamed('home', places), home);
    expect(savedPlaceNamed('the clinic', places), clinic);
    expect(savedPlaceNamed('go back home', places), isNull);
    expect(savedPlaceNamed('help me get home', places), isNull);
    expect(savedPlaceNamed('clinic near the church', places), isNull);
  });

  test('nothing is guessed', () {
    expect(matchSavedPlace('school', places), isNull,
        reason: 'no school is saved');
    expect(matchSavedPlace('jollibee', places), isNull);
    expect(matchSavedPlace('', places), isNull);
  });

  group('places found by name', () {
    test('read latitude first, with duplicates and nameless ones left out', () {
      final found = parsePhoton(map.photonJollibee);
      expect(found.map((p) => p.label), ['Jollibee', 'Jollibee', 'Jollibee']);
      expect(found.first.latitude, 14.8433);
      expect(found.first.longitude, 120.8145);
      expect(found.first.street, 'Paseo del Congreso');
      expect(found.first.area, 'Malolos');
      expect(found[1].area, 'Longos', reason: 'a district, when there is no city');
    });

    test('two branches with one name and one street are both offered', () {
      final found = parsePhoton({
        'features': [
          for (final (lon, lat, city) in [
            (120.8237, 14.8499, 'Malolos'),
            (120.8739, 14.8282, 'Guiguinto'),
          ])
            {
              'geometry': {'coordinates': [lon, lat]},
              'properties': {
                'osm_type': 'N',
                'osm_id': city.length,
                'name': 'Jollibee',
                'street': 'MacArthur Highway',
                'city': city,
              },
            },
        ],
      });
      expect(found.map((p) => p.area), ['Malolos', 'Guiguinto']);
    });

    test('far away is not what someone walking means', () {
      final near = nearbyCandidates(parsePhoton(map.photonJollibee), map.a);
      expect(near.map((p) => p.street), ['Paseo del Congreso', 'MacArthur Highway']);
    });

    test('each is described so it can be told apart by ear', () {
      final jollibee = parsePhoton(map.photonJollibee).first;
      expect(describeCandidate(jollibee, from: map.a),
          'Jollibee, Paseo del Congreso, Malolos, about 600 metres away.');
      expect(candidateQuestion(jollibee, more: true),
          'Jollibee, Paseo del Congreso, Malolos. Say yes to go there, next for another, or no.');
      expect(candidateQuestion(jollibee, more: false),
          endsWith('Say yes to go there, or no.'));
    });

    test('an address with no name is called by its address', () {
      const house = PlaceCandidate(
          latitude: 1, longitude: 2, street: 'Rizal Street', houseNumber: '12');
      expect(house.label, '12 Rizal Street');
      expect(house.toDestination().label, '12 Rizal Street');
    });

    test('choosing the same place twice is the same destination', () {
      final first = parsePhoton(map.photonJollibee).first;
      final again = parsePhoton(map.photonJollibee).first;
      expect(first.toDestination(), again.toDestination());
      expect(first.toDestination().id, 'search-N1111');
    });

    test('where am I: the street and the town', () {
      final here = parsePhoton(map.photonReverseAtA).single;
      expect(nearbyDescription(here), 'near Rizal Street, Malolos');
    });

    test('an answer that is not a place list is the service failing', () {
      expect(
        () => parsePhoton({'message': 'rate limited'}),
        throwsA(isA<MapServiceException>().having(
            (e) => e.failure, 'failure', MapServiceFailure.unavailable)),
      );
    });
  });

  group('what a search says about the position it used', () {
    final now = DateTime.utc(2026, 9, 18, 10);
    LocationFix at(Duration ago) => LocationFix(
        latitude: 14.79, longitude: 120.92, accuracyMetres: 10, at: now.subtract(ago));

    test('none at all: results may be far', () {
      expect(searchNote(null, now: now),
          'Searching without your position, so results may be far.');
    });

    test('an old one is said to be old', () {
      expect(searchNote(at(const Duration(minutes: 5)), now: now),
          'Using where you were 5 minutes ago.');
    });

    test('a fresh one needs no note', () {
      expect(searchNote(at(const Duration(seconds: 20)), now: now), isNull);
    });
  });
}
