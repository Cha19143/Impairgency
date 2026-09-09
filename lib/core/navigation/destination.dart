/// Somewhere the user has said they are going, or somewhere they go often
/// enough to want a button for.
///
/// Home, work and school are the three the tester named; anything else is
/// [DestinationKind.other] with a label. A place is a point, not a route:
/// the guidance built on it is straight-line, and `guidance.dart` says so.
library;

enum DestinationKind { home, work, school, other }

const Map<DestinationKind, String> kDestinationKindLabels = {
  DestinationKind.home: 'Home',
  DestinationKind.work: 'Work',
  DestinationKind.school: 'School',
  DestinationKind.other: 'Somewhere else',
};

/// The three fixed buttons, in the order they appear.
const List<DestinationKind> kReadyMadeKinds = [
  DestinationKind.home,
  DestinationKind.work,
  DestinationKind.school,
];

DestinationKind destinationKindFromKey(String? key) {
  for (final kind in DestinationKind.values) {
    if (kind.name == key) return kind;
  }
  return DestinationKind.other;
}

class Destination {
  const Destination({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.kind = DestinationKind.other,
  });

  /// The document id. Home, work and school use their kind as the id so
  /// there is exactly one of each; others get a generated one.
  final String id;

  final String label;
  final double latitude;
  final double longitude;
  final DestinationKind kind;

  Map<String, Object?> toJson() => {
        'label': label,
        'lat': latitude,
        'lng': longitude,
        'kind': kind.name,
      };

  static Destination? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    final label = raw['label'];
    if (lat is! num || lng is! num || label is! String) return null;
    return Destination(
      id: id,
      label: label,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      kind: destinationKindFromKey(raw['kind'] as String?),
    );
  }

  Destination copyWith({String? label}) => Destination(
        id: id,
        label: label ?? this.label,
        latitude: latitude,
        longitude: longitude,
        kind: kind,
      );

  @override
  bool operator ==(Object other) => other is Destination && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The id a new place gets: the kind's name for the fixed three, so saving
/// Home twice replaces Home rather than making a second one.
String destinationIdFor(DestinationKind kind, {required String Function() fresh}) =>
    kind == DestinationKind.other ? fresh() : kind.name;

/// Ready-made first, in their fixed order, then everything else by label.
List<Destination> orderForButtons(List<Destination> places) {
  final fixed = <Destination>[];
  for (final kind in kReadyMadeKinds) {
    final match = places.where((p) => p.kind == kind).firstOrNull;
    if (match != null) fixed.add(match);
  }
  final others = places.where((p) => p.kind == DestinationKind.other).toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return [...fixed, ...others];
}

/// Why a place cannot be saved, or null if it can.
String? validateDestinationLabel(String label, {required DestinationKind kind}) {
  if (kind != DestinationKind.other) return null;
  if (label.trim().isEmpty) return 'Give this place a name.';
  if (label.trim().length > 40) return 'Use a shorter name.';
  return null;
}
