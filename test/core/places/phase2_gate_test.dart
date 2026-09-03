import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/places/journey.dart';
import 'package:impairgency/core/places/place.dart';
import 'package:impairgency/core/places/routine.dart';
import 'package:impairgency/core/places/session_event.dart';
import 'package:impairgency/core/places/stay.dart';
import 'package:impairgency/core/places/timeline.dart';

/// The Phase 2 gate, asserted rather than asserted-to.
///
/// The claim the whole phase rests on is that four requirements — §2.B.2
/// environment learning, §2.B.1 routine learning, §2.A.7 travel recording and
/// §1.3 frequent locations — are aggregations over **one** collection of
/// timestamped fixes, with no model anywhere. This test feeds a fortnight of
/// one plausible life into that collection and gets all four back out.
void main() {
  const home = (lat: 14.7942, lng: 120.9214);
  const clinic = (lat: 14.7680, lng: 120.9464);

  /// Readings once a minute, in one spot, with a little indoor drift.
  List<LocationFix> lingering(
    ({double lat, double lng}) p,
    DateTime from,
    Duration span,
  ) =>
      List.generate(span.inMinutes + 1, (i) {
        final drift = (i % 5 - 2) * 8 / 111320.0;
        return LocationFix(
          latitude: p.lat + drift,
          longitude: p.lng,
          accuracyMetres: 12,
          at: from.add(Duration(minutes: i)),
        );
      });

  /// A fortnight: home every night, the clinic every weekday morning.
  List<LocationFix> fortnight() {
    final fixes = <LocationFix>[];
    for (var day = 0; day < 14; day++) {
      // 31 August 2026 is a Monday.
      final date = DateTime.utc(2026, 8, 31).add(Duration(days: day));
      final isWeekday = date.weekday <= 5;

      fixes.addAll(lingering(
          home, date.add(const Duration(hours: 6)), const Duration(minutes: 90)));

      if (isWeekday) {
        // Travelling, at a plausible speed, so the walk is not a stay.
        for (var i = 1; i <= 25; i++) {
          fixes.add(LocationFix(
            latitude: home.lat + (clinic.lat - home.lat) * i / 25,
            longitude: home.lng + (clinic.lng - home.lng) * i / 25,
            accuracyMetres: 15,
            at: date.add(Duration(hours: 8, minutes: i)),
          ));
        }
        fixes.addAll(lingering(clinic,
            date.add(const Duration(hours: 8, minutes: 30)),
            const Duration(minutes: 120)));
      }
    }
    return fixes;
  }

  test('one collection of fixes yields all four requirements', () {
    final fixes = fortnight();

    // ---- §2.B.2 environment learning: places the user returns to ----------
    final places = clusterIntoPlaces(detectStays(fixes));
    expect(places.length, greaterThanOrEqualTo(2),
        reason: 'home and the clinic should both emerge');

    final frequent = frequentPlaces(places);
    expect(frequent.length, greaterThanOrEqualTo(2));

    // ---- §1.3 frequently visited locations: ordered by visit count --------
    expect(frequent.first.visitCount, greaterThanOrEqualTo(frequent.last.visitCount),
        reason: 'most visited first is what the dashboard panel shows');
    final labelled = frequent.first.copyWith(label: 'Home');
    expect(labelled.label, 'Home');

    // ---- §2.B.1 routine learning: a schedule, in local time ---------------
    final manila = const Duration(hours: 8);
    final described = frequent
        .map((p) => describeRoutine(p, offset: manila))
        .whereType<String>()
        .toList();
    expect(described, isNotEmpty,
        reason: 'a fortnight of the same pattern is enough to describe');
    expect(described.first, contains('visits so far'),
        reason: 'the count travels with the claim so it can be checked');

    // ---- §2.A.7 travel recording: a replayable path -----------------------
    final morning = fixes
        .where((f) =>
            f.at.isAfter(DateTime.utc(2026, 8, 31, 7, 59)) &&
            f.at.isBefore(DateTime.utc(2026, 8, 31, 10, 31)))
        .toList();
    final journey = journeyFrom('2026-08-31-am', morning);

    expect(journey.path.length, greaterThan(10));
    expect(journey.metresTravelled, greaterThan(3000),
        reason: 'home to the clinic is about 4 km');
    expect(journey.discarded, 0, reason: 'this trace is clean');
    expect(describeDistance(journey.metresTravelled), contains('kilometres'));

    // ---- §1.1 substitute: the review timeline -----------------------------
    final timeline = buildTimeline(journey, [
      SessionEvent(
        id: 'a',
        sessionId: '2026-08-31-am',
        at: DateTime.utc(2026, 8, 31, 8, 12),
        kind: SessionEventKind.obstacleDetected,
        detail: 'chair',
      ),
      SessionEvent(
        id: 'b',
        sessionId: '2026-08-31-am',
        at: DateTime.utc(2026, 8, 31, 8, 21),
        kind: SessionEventKind.stairsDetected,
      ),
    ]);

    expect(timeline.rows, hasLength(2));
    expect(timeline.rows.first.stamp, isNotEmpty);
    expect(timeline.summary, contains('events'));
    expect(timeline.needsAttention, isFalse,
        reason: 'an ordinary session raises no concerns');
  });

  test('and none of it needed a model, a label, or a training set', () {
    // The defensible claim: everything above is counting. If this test can be
    // read end to end by someone who does not do machine learning, the feature
    // can be explained to a panel in one slide.
    final places = clusterIntoPlaces(detectStays(fortnight()));
    for (final place in places) {
      expect(place.label, isNull, reason: 'no name is ever invented');
      expect(place.visitCount, greaterThan(0));
    }
  });
}
