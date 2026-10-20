/// Finding the place someone asked to go to.
///
/// "Take me home", "dalhin ako sa trabaho", "navigate to the clinic": the words
/// are matched against the places the user has saved first - they are known,
/// they work offline, and they are what someone means by "home". Anything else
/// is looked up on OpenStreetMap, and what comes back is read here. Pure, so
/// every wording is tested without a map.
library;

import '../location/location_fix.dart';
import '../location/location_policy.dart' show describeAge;
import '../places/geo.dart';
import 'destination.dart';
import 'guidance.dart';
import 'map_services.dart';
import 'route.dart';

/// Words people use for the three ready-made places, in English and Filipino.
const Map<DestinationKind, Set<String>> kPlaceKindWords = {
  DestinationKind.home: {'home', 'my house', 'bahay', 'bahay namin', 'tahanan'},
  DestinationKind.work: {'work', 'the office', 'office', 'trabaho', 'opisina'},
  DestinationKind.school: {
    'school',
    'paaralan',
    'eskwela',
    'eskwelahan',
    'iskul',
  },
};

String _normalise(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty && w != 'the' && w != 'my' && w != 'ang')
    .join(' ');

/// The saved place [query] is the whole name of, or null.
///
/// Home, work and school answer to their words ("bahay" is home) as well as
/// to whatever label they were saved under. Any other place matches by its
/// label, ignoring case, punctuation and a leading "the" or "my" - "the
/// clinic" finds "Clinic".
///
/// For a place name said on its own, as the answer to "where are you
/// going?". Nothing else is taken out of a longer phrase: "go back home" is
/// the way back, not directions to Home.
Destination? savedPlaceNamed(String query, List<Destination> places) {
  final wanted = _normalise(query);
  if (wanted.isEmpty) return null;

  for (final place in places) {
    if (_normalise(place.label) == wanted) return place;
  }
  for (final place in places) {
    final words = kPlaceKindWords[place.kind];
    if (words != null && words.map(_normalise).contains(wanted)) return place;
  }
  return null;
}

/// The saved place [query] names, or null if none does.
///
/// For what follows "take me to": the whole name first, as
/// [savedPlaceNamed], then a saved name inside a longer description.
Destination? matchSavedPlace(String query, List<Destination> places) {
  final named = savedPlaceNamed(query, places);
  if (named != null) return named;
  final wanted = _normalise(query);
  if (wanted.isEmpty) return null;

  // "clinic near the market" still finds "Clinic" - but only when exactly
  // one saved label is inside what was said, so a guess is never made
  // between two.
  final contained = [
    for (final place in places)
      if (_normalise(place.label).isNotEmpty &&
          ' $wanted '.contains(' ${_normalise(place.label)} '))
        place,
  ];
  return contained.length == 1 ? contained.single : null;
}

/// A place the map service found by name: a shop, a street, a barangay hall.
class PlaceCandidate {
  const PlaceCandidate({
    required this.latitude,
    required this.longitude,
    this.name = '',
    this.street = '',
    this.houseNumber = '',
    this.area = '',
    this.id = '',
  });

  final double latitude;
  final double longitude;

  /// Its own name, if it has one. An address does not.
  final String name;
  final String street;
  final String houseNumber;

  /// The town, city or district it is in.
  final String area;

  /// Stable for the same place, so choosing it twice is one destination.
  final String id;

  RoutePoint get point => RoutePoint(latitude, longitude);

  /// Street and town, for a history entry. Empty when the map named neither.
  String get addressLine {
    final streetLine = [
      if (houseNumber.isNotEmpty) houseNumber,
      if (street.isNotEmpty) street,
    ].join(' ');
    return [
      if (streetLine.isNotEmpty) streetLine,
      if (area.isNotEmpty) area,
    ].join(', ');
  }

  /// What to call it: its name, else its address, else its area.
  String get label {
    if (name.isNotEmpty) return name;
    if (street.isNotEmpty) {
      return houseNumber.isEmpty ? street : '$houseNumber $street';
    }
    return area;
  }

  Destination toDestination() => Destination(
    id: 'search-$id',
    label: label,
    latitude: latitude,
    longitude: longitude,
    address: addressLine,
  );
}

/// Places in a Photon answer - GeoJSON features, coordinates `[lon, lat]` -
/// with anything unnamed and unaddressed left out, since it could not be
/// said.
List<PlaceCandidate> parsePhoton(Object? json) {
  if (json is! Map) {
    throw const MapServiceException(
      MapServiceFailure.unavailable,
      'not a JSON object',
    );
  }
  final features = json['features'];
  if (features is! List) {
    throw const MapServiceException(
      MapServiceFailure.unavailable,
      'no features',
    );
  }
  final found = <PlaceCandidate>[];
  for (final feature in features) {
    if (feature is! Map) continue;
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    if (geometry is! Map || properties is! Map) continue;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List ||
        coordinates.length < 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      continue;
    }
    String text(String key) {
      final value = properties[key];
      return value is String ? value.trim() : '';
    }

    final area = [
      text('city'),
      text('locality'),
      text('district'),
      text('county'),
    ].firstWhere((a) => a.isNotEmpty, orElse: () => '');
    final candidate = PlaceCandidate(
      latitude: (coordinates[1] as num).toDouble(),
      longitude: (coordinates[0] as num).toDouble(),
      name: text('name'),
      street: text('street'),
      houseNumber: text('housenumber'),
      area: area,
      id: '${text('osm_type')}${properties['osm_id'] ?? ''}',
    );
    if (candidate.label.isEmpty) continue;
    // The same shop mapped as a point and as a building comes back twice, a
    // few metres apart. Two branches on the same highway are kilometres
    // apart, and both are worth offering - the recorded search found two
    // Jollibees on MacArthur Highway, in different towns.
    final label = candidate.label.toLowerCase();
    if (found.any(
      (f) =>
          f.label.toLowerCase() == label &&
          metresBetween(
                f.latitude,
                f.longitude,
                candidate.latitude,
                candidate.longitude,
              ) <
              kSamePlaceMetres,
    )) {
      continue;
    }
    found.add(candidate);
  }
  return found;
}

/// Two results with one name this close together are one place.
const double kSamePlaceMetres = 60;

/// Found places further than this are not what someone walking means.
const double kSearchRadiusMetres = 30000;

/// [candidates] within [kSearchRadiusMetres] of [from], in the order the
/// service ranked them.
List<PlaceCandidate> nearbyCandidates(
  List<PlaceCandidate> candidates,
  RoutePoint from,
) => [
  for (final c in candidates)
    if (metresBetween(from.latitude, from.longitude, c.latitude, c.longitude) <=
        kSearchRadiusMetres)
      c,
];

/// A position older than this is said to be old when a search uses it.
const Duration kStaleSearchFix = Duration(minutes: 2);

/// What to say before a search's results about the position it used: none
/// at all, or one some minutes old. Null for a fresh one.
String? searchNote(LocationFix? fix, {required DateTime now}) {
  if (fix == null) {
    return 'Searching without your position, so results may be far.';
  }
  final age = now.difference(fix.at);
  if (age > kStaleSearchFix) {
    return 'Using where you were ${describeAge(age)}.';
  }
  return null;
}

/// "Jollibee, MacArthur Highway, Malolos, about 850 metres away."
String describeCandidate(PlaceCandidate candidate, {RoutePoint? from}) {
  final parts = <String>[candidate.label];
  if (candidate.name.isNotEmpty && candidate.street.isNotEmpty) {
    parts.add(candidate.street);
  }
  if (candidate.area.isNotEmpty &&
      !parts.any((p) => p.toLowerCase() == candidate.area.toLowerCase())) {
    parts.add(candidate.area);
  }
  final where = parts.join(', ');
  if (from == null) return '$where.';
  final metres = metresBetween(
    from.latitude,
    from.longitude,
    candidate.latitude,
    candidate.longitude,
  );
  return '$where, ${describeDistance(metres)} away.';
}

/// Asked about each place found, one at a time.
String candidateQuestion(
  PlaceCandidate candidate, {
  RoutePoint? from,
  required bool more,
}) =>
    '${describeCandidate(candidate, from: from)} '
    '${more ? 'Say yes to go there, next for another, or no.' : 'Say yes to go there, or no.'}';

/// "near MacArthur Highway, Malolos" - for "where am I", from what the map
/// service says is at the position. Null if it said nothing sayable.
String? nearbyDescription(PlaceCandidate candidate) {
  final street = candidate.street.isNotEmpty
      ? candidate.street
      : candidate.name;
  final parts = [
    if (street.isNotEmpty) street,
    if (candidate.area.isNotEmpty &&
        candidate.area.toLowerCase() != street.toLowerCase())
      candidate.area,
  ];
  return parts.isEmpty ? null : 'near ${parts.join(', ')}';
}
