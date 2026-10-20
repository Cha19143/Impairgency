import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/alerts/alert_presenter.dart';
import 'package:impairgency/core/alerts/guardian_alert.dart';
import 'package:impairgency/guardian/guardian_alert_watcher.dart';

void main() {
  final now = DateTime.utc(2026, 10, 20, 12);
  late RecordingAlertPresenter presenter;
  late StreamController<List<GuardianAlert>> alerts;
  late GuardianAlertWatcher watcher;

  GuardianAlert item(String id, String kind) => GuardianAlert(
    id: id,
    userId: 'vi-1',
    kind: kind,
    message: 'stored',
    at: now,
    latitude: 14.6,
    longitude: 120.98,
  );

  setUp(() {
    presenter = RecordingAlertPresenter();
    alerts = StreamController<List<GuardianAlert>>();
    watcher = GuardianAlertWatcher(
      presenter: presenter,
      nameOf: (id) => id == 'vi-1' ? 'Ana' : null,
      now: () => now,
    );
  });

  tearDown(() async {
    await watcher.stop();
    await alerts.close();
  });

  test('names Ana for a route deviation and a one-hour stay, once each', () async {
    await watcher.start(alerts.stream);
    alerts.add([
      item('a', kGuardianAlertRouteDeviation),
      item('b', kGuardianAlertStationary),
    ]);
    await Future<void>.delayed(Duration.zero);
    alerts.add([
      item('a', kGuardianAlertRouteDeviation),
      item('b', kGuardianAlertStationary),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(presenter.shown.map((a) => a.title), [
      'Ana left the planned route',
      'Ana has been in one place for 1 hour',
    ]);
    expect(presenter.shown.first.payload, 'live:vi-1');
  });
}
