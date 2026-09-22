import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/alerts/alert_presenter.dart';
import 'package:impairgency/core/alerts/sos_alert.dart';
import 'package:impairgency/guardian/sos_watcher.dart';

final now = DateTime.utc(2026, 9, 3, 12, 0);

SosEvent event(String id,
        {Duration age = Duration.zero,
        String user = 'vi-1',
        bool cancelled = false,
        Duration? resolvedAgo}) =>
    SosEvent(
      id: id,
      userId: user,
      at: now.subtract(age),
      cancelled: cancelled,
      resolvedAt: resolvedAgo == null ? null : now.subtract(resolvedAgo),
      resolvedBy: resolvedAgo == null ? null : 'user',
    );

void main() {
  late RecordingAlertPresenter presenter;
  late StreamController<List<SosEvent>> events;
  late SosWatcher watcher;

  setUp(() {
    presenter = RecordingAlertPresenter();
    events = StreamController<List<SosEvent>>();
    watcher = SosWatcher(
      presenter: presenter,
      nameOf: (id) => {'vi-1': 'Bob Doe', 'vi-2': 'Ana Reyes'}[id],
      now: () => now,
    );
  });

  tearDown(() async {
    await watcher.stop();
    await events.close();
  });

  Future<void> emit(List<SosEvent> batch) async {
    events.add(batch);
    await Future<void>.delayed(Duration.zero);
  }

  test('prepares the channel before it can miss anything', () async {
    await watcher.start(events.stream);
    expect(presenter.prepares, 1);
  });

  test('alerts on a live SOS, naming the person', () async {
    await watcher.start(events.stream);
    await emit([event('e1')]);

    expect(presenter.shown, hasLength(1));
    expect(presenter.shown.single.title, 'Bob Doe needs help');
  });

  test('does not alert twice for the same event', () async {
    // Firestore re-emits the whole result set on every change, so the same
    // document arrives again the moment a second one appears.
    await watcher.start(events.stream);
    await emit([event('e1')]);
    await emit([event('e1')]);
    await emit([event('e1'), event('e2')]);

    expect(presenter.shown.map((a) => a.eventId), ['e1', 'e2']);
  });

  test('stays quiet for history when the listener first attaches', () async {
    await watcher.start(events.stream);
    await emit([
      event('old-1', age: const Duration(days: 3)),
      event('old-2', age: const Duration(hours: 6)),
    ]);

    expect(presenter.shown, isEmpty);
  });

  test('stays quiet for a cancelled SOS', () async {
    await watcher.start(events.stream);
    await emit([event('e1', cancelled: true)]);

    expect(presenter.shown, isEmpty);
  });

  test('shows the newest last, so it is the one on top', () async {
    await watcher.start(events.stream);
    await emit([
      event('older', age: const Duration(minutes: 5)),
      event('newer', age: const Duration(minutes: 1)),
    ]);

    expect(presenter.shown.map((a) => a.eventId), ['older', 'newer']);
  });

  test('handles more than one watched user', () async {
    await watcher.start(events.stream);
    await emit([event('e1', user: 'vi-1'), event('e2', user: 'vi-2')]);

    expect(presenter.shown.map((a) => a.title),
        ['Bob Doe needs help', 'Ana Reyes needs help']);
  });

  test('falls back gracefully for a user it has no name for', () async {
    await watcher.start(events.stream);
    await emit([event('e1', user: 'unknown')]);

    expect(presenter.shown.single.title, 'Someone you watch over needs help');
  });

  test('stops listening when told to', () async {
    await watcher.start(events.stream);
    await watcher.stop();
    await emit([event('e1')]);

    expect(presenter.shown, isEmpty);
  });

  test('"I am okay" after the call is shown once, and only once', () async {
    await watcher.start(events.stream);
    await emit([event('e1', age: const Duration(minutes: 2))]);
    await emit([
      event('e1',
          age: const Duration(minutes: 2), resolvedAgo: Duration.zero),
    ]);
    // Firestore sends the whole set again on every change.
    await emit([
      event('e1',
          age: const Duration(minutes: 2), resolvedAgo: Duration.zero),
    ]);

    expect(presenter.shown.map((a) => a.title),
        ['Bob Doe needs help', 'Bob Doe says they are okay']);
  });

  test('an emergency already over when first seen raises only the all-clear',
      () async {
    await watcher.start(events.stream);
    await emit([
      event('e1',
          age: const Duration(minutes: 3),
          resolvedAgo: const Duration(minutes: 1)),
    ]);
    expect(presenter.shown.map((a) => a.title),
        ['Bob Doe says they are okay']);
  });
}
