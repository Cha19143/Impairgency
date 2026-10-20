import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/alerts/guardian_alert.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/core/motion/fall_event.dart';
import 'package:impairgency/data/guardian_alert_repository.dart';

class _Alerts implements GuardianAlertSink {
  final sent = <String>[];

  @override
  Future<void> send({
    required String uid,
    required String kind,
    required String message,
    required DateTime at,
    double? latitude,
    double? longitude,
  }) async {
    sent.add(kind);
  }
}

class _Falls implements FallHistorySink {
  final rows = <FallMoment>[];

  @override
  Future<void> record(
    String uid,
    FallMoment moment, {
    required String sessionId,
  }) async {
    rows.add(moment);
  }
}

class _Here implements LocationSource {
  @override
  Future<LocationAvailability> availability() async =>
      LocationAvailability.ready;

  @override
  Future<LocationAvailability> requestPermission() async =>
      LocationAvailability.ready;

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 8),
  }) async => LocationFix(
    latitude: 14.6,
    longitude: 120.98,
    accuracyMetres: 8,
    at: DateTime.utc(2026, 10, 20, 9),
  );

  @override
  Future<LocationFix?> lastKnownFix() async => null;
}

void main() {
  late _Alerts alerts;
  late _Falls falls;
  late AppSession session;

  setUp(() {
    alerts = _Alerts();
    falls = _Falls();
    session = AppSession(
      guardianAlerts: alerts,
      fallHistory: falls,
      location: _Here(),
    );
  });

  Future<void> finish(bool answered) async {
    session.noteImportantFall();
    await session.completeImportantFall(answered: answered);
    await pumpEventQueue();
  }

  test('no answer alerts the guardian and, with history on, writes the fall', () async {
    session.update(
      const SessionState(
        uid: 'u1',
        signedIn: true,
        consent: {'location': true, 'history': true},
      ),
    );
    await finish(false);
    expect(alerts.sent, [kGuardianAlertFall]);
    expect(falls.rows.single.answered, isFalse);
    expect(falls.rows.single.position?.latitude, 14.6);
  });

  test('an answer is logged and does not alert', () async {
    session.update(
      const SessionState(
        uid: 'u1',
        signedIn: true,
        consent: {'location': true, 'history': true},
      ),
    );
    await finish(true);
    expect(alerts.sent, isEmpty);
    expect(falls.rows.single.answered, isTrue);
  });

  test('history off still alerts, and location off still logs', () async {
    session.update(
      const SessionState(
        uid: 'u1',
        signedIn: true,
        consent: {'location': true, 'history': false},
      ),
    );
    await finish(false);
    expect(alerts.sent, [kGuardianAlertFall]);
    expect(falls.rows, isEmpty);

    session.update(
      const SessionState(
        uid: 'u1',
        signedIn: true,
        consent: {'location': false, 'history': true},
      ),
    );
    await finish(false);
    expect(alerts.sent, [kGuardianAlertFall]);
    expect(falls.rows.single.answered, isFalse);
  });

  test('leaving the screen writes nothing', () async {
    session.update(
      const SessionState(
        uid: 'u1',
        signedIn: true,
        consent: {'location': true, 'history': true},
      ),
    );
    session.noteImportantFall();
    session.cancelImportantFall();
    await session.completeImportantFall(answered: false);
    await pumpEventQueue();
    expect(alerts.sent, isEmpty);
    expect(falls.rows, isEmpty);
  });
}
