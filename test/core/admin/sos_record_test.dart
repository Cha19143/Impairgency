import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/admin/sos_record.dart';
import 'package:impairgency/core/places/session_summary.dart';

DateTime? _date(Object? value) => value is DateTime ? value : null;

SosRecord record(Map<String, Object?> data) =>
    SosRecord.fromJson('e1', data, toDate: _date);

void main() {
  final at = DateTime.utc(2026, 9, 18, 10);

  test('reads what the phone wrote', () {
    final r = record({
      'userId': 'u1',
      'at': at,
      'lat': 14.79,
      'lng': 120.92,
      'accuracy': 12,
      'locationSummary': 'Your location was sent.',
      'contact': {'name': 'Mum', 'number': '0917'},
      'cancelled': false,
      'status': 'active',
    });
    expect(r.userId, 'u1');
    expect(r.at, at);
    expect(r.contactName, 'Mum');
    expect(r.status, SosStatus.active);
    expect(r.statusLabel, 'Active');
    expect(r.mapLink.toString(),
        'https://www.openstreetmap.org/?mlat=14.79&mlon=120.92#map=18/14.79/120.92');
  });

  test('a cancelled countdown, and one cancelled after the alarm', () {
    expect(record({'userId': 'u1', 'cancelled': true}).statusLabel,
        'Cancelled');
    expect(
        record({'userId': 'u1', 'cancelled': true, 'stage': 'before-call'})
            .statusLabel,
        'Cancelled before the call');
  });

  test('resolved by the user, or by an administrator', () {
    final byUser =
        record({'userId': 'u1', 'resolvedAt': at, 'resolvedBy': 'user'});
    expect(byUser.status, SosStatus.resolved);
    expect(byUser.statusLabel, 'Resolved by user');
    // The server timestamp is not there yet on a write just made; who did
    // it is enough.
    expect(record({'userId': 'u1', 'resolvedBy': 'admin-1'}).statusLabel,
        'Resolved by admin');
  });

  test('no position, no map link', () {
    expect(record({'userId': 'u1'}).mapLink, isNull);
  });

  test('incidents are the ones that were sent', () {
    expect(
        sosIncidentsIn([
          record({'userId': 'u1'}),
          record({'userId': 'u1', 'resolvedBy': 'user'}),
          record({'userId': 'u1', 'cancelled': true}),
        ]),
        2);
  });

  group('the overview, without journeys', () {
    // Journeys are only recorded with history on. Emergencies and users who
    // shared a position are counted anyway.
    test('counts emergencies and active users from elsewhere', () {
      final o = overviewOf(const [], sosIncidents: 2, alsoActive: {'u1', 'u2'});
      expect(o.sessions, 0);
      expect(o.sosIncidents, 2);
      expect(o.activeUsers, 2);
    });

    test('a user with a journey and a shared position counts once', () {
      final o = overviewOf([
        SessionSummary(
          sessionId: 's1',
          userId: 'u1',
          startedAt: at,
          duration: const Duration(minutes: 5),
          metresTravelled: 300,
          eventCounts: const {},
          discardedFraction: 0,
          concernCount: 0,
          placeLabels: const [],
        ),
      ], alsoActive: {'u1', 'u2'});
      expect(o.activeUsers, 2);
    });
  });
}
