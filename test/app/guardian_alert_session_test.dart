import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/alerts/guardian_alert.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/data/guardian_alert_repository.dart';

class _Alerts implements GuardianAlertSink {
  final sent = <({String kind, String message, double? latitude})>[];

  @override
  Future<void> send({
    required String uid,
    required String kind,
    required String message,
    required DateTime at,
    double? latitude,
    double? longitude,
  }) async {
    sent.add((kind: kind, message: message, latitude: latitude));
  }
}

void main() {
  late _Alerts alerts;
  late AppSession session;

  final t0 = DateTime.utc(2026, 10, 20, 8);

  LocationFix fix(int minutes, {double lat = 14.6}) => LocationFix(
    latitude: lat,
    longitude: 120.98,
    accuracyMetres: 8,
    at: t0.add(Duration(minutes: minutes)),
  );

  setUp(() {
    alerts = _Alerts();
    session = AppSession(guardianAlerts: alerts);
    session.update(
      const SessionState(
        uid: 'u1',
        signedIn: true,
        consent: {'location': true, 'history': false},
      ),
    );
    session.setForeground(true);
  });

  test('a route deviation alerts once inside five minutes, without history consent', () async {
    session.recordRouteDeviation(fix(0), 40);
    session.recordRouteDeviation(fix(1), 40);
    await pumpEventQueue();
    expect(alerts.sent.map((a) => a.kind), [kGuardianAlertRouteDeviation]);
  });

  test('no location consent means no guardian alert', () async {
    session.update(
      const SessionState(
        uid: 'u1',
        signedIn: true,
        consent: {'location': false, 'history': true},
      ),
    );
    session.recordRouteDeviation(fix(0), 40);
    await pumpEventQueue();
    expect(alerts.sent, isEmpty);
  });

  test('an hour in one place alerts once, and Home does not', () async {
    await session.store.cachePlaces([
      const Destination(
        id: 'home',
        label: 'Home',
        kind: DestinationKind.home,
        latitude: 14.7,
        longitude: 120.98,
      ),
    ]);

    for (var m = 0; m <= 60; m += 5) {
      session.noteStationaryReading(fix(m));
    }
    await pumpEventQueue();
    expect(alerts.sent.map((a) => a.kind), [kGuardianAlertStationary]);

    for (var m = 0; m <= 120; m += 5) {
      session.noteStationaryReading(fix(m, lat: 14.7));
    }
    await pumpEventQueue();
    expect(alerts.sent.map((a) => a.kind), [kGuardianAlertStationary]);
  });
}
