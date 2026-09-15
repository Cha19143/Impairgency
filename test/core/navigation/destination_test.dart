import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/navigation/destination.dart';

const home = Destination(
    id: 'home', label: 'Home', latitude: 1, longitude: 2, kind: DestinationKind.home);
const school = Destination(
    id: 'school', label: 'School', latitude: 1, longitude: 2, kind: DestinationKind.school);
const clinic = Destination(id: 'p1', label: 'Clinic', latitude: 1, longitude: 2);
const aunt = Destination(id: 'p2', label: "Auntie's", latitude: 1, longitude: 2);

void main() {
  test('the ready-made three come first, in their order, then the rest by name',
      () {
    final ordered = orderForButtons([clinic, school, aunt, home]);
    expect(ordered.map((p) => p.label), ['Home', 'School', "Auntie's", 'Clinic']);
  });

  test('home, work and school each have exactly one spot', () {
    expect(destinationIdFor(DestinationKind.home, fresh: () => 'x'), 'home');
    expect(destinationIdFor(DestinationKind.other, fresh: () => 'x'), 'x');
  });

  test('round-trips through the document, and refuses junk', () {
    final json = clinic.toJson();
    expect(Destination.fromJson('p1', json), clinic);
    expect(Destination.fromJson('p1', json)!.label, 'Clinic');
    expect(Destination.fromJson('p1', {'label': 'x'}), isNull);
    expect(Destination.fromJson('p1', 'junk'), isNull);
    expect(destinationKindFromKey('school'), DestinationKind.school);
    expect(destinationKindFromKey('castle'), DestinationKind.other);
  });

  test('somewhere else needs a name; the fixed three do not', () {
    expect(validateDestinationLabel('', kind: DestinationKind.home), isNull);
    expect(validateDestinationLabel('', kind: DestinationKind.other),
        contains('name'));
    expect(validateDestinationLabel('Clinic', kind: DestinationKind.other),
        isNull);
  });

  test('a found place with a long name is cut at a word to fit', () {
    expect(shortPlaceLabel('Jollibee'), 'Jollibee');
    expect(
        shortPlaceLabel(
            'Bulacan Medical Center Emergency Room Entrance and Parking'),
        'Bulacan Medical Center Emergency Room');
    expect(validateDestinationLabel(
            shortPlaceLabel('x' * 60), kind: DestinationKind.other),
        isNull);
  });
}
