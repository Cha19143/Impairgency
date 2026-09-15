import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/data/location_sharer.dart';

/// The thing that finally writes a position for the guardian. Before it, the
/// guardian's card said "sharing their location, but none has been recorded
/// yet" forever: nothing in the user app ever published one.
class _Source implements LocationSource {
  LocationAvailability availability_ = LocationAvailability.ready;
  LocationAvailability? onRequest;
  LocationFix? next;
  int asked = 0;
  int prompted = 0;

  @override
  Future<LocationAvailability> availability() async => availability_;

  @override
  Future<LocationAvailability> requestPermission() async {
    prompted++;
    if (onRequest != null) availability_ = onRequest!;
    return availability_;
  }

  @override
  Future<LocationFix?> currentFix({Duration? timeout}) async {
    asked++;
    return next;
  }

  @override
  Future<LocationFix?> lastKnownFix() async => next;
}

class _Sink implements LastFixSink {
  final published = <(String, LocationFix)>[];
  final cleared = <String>[];
  Object? failWith;

  @override
  Future<void> publish(String uid, LocationFix fix) async {
    if (failWith != null) throw failWith!;
    published.add((uid, fix));
  }

  @override
  Future<void> clear(String uid) async => cleared.add(uid);
}

void main() {
  final t0 = DateTime.utc(2026, 9, 13, 8);
  LocationFix fix(double lat, DateTime when) =>
      LocationFix(latitude: lat, longitude: 121, accuracyMetres: 10, at: when);

  late _Source source;
  late _Sink sink;
  late List<(String, LocationFix)> history;
  late DateTime now;

  LocationSharer make() => LocationSharer(
        source: source,
        sink: sink,
        recordHistory: (uid, f) async => history.add((uid, f)),
        interval: const Duration(days: 1), // the tests drive poll() themselves
        now: () => now,
      );

  setUp(() {
    source = _Source();
    sink = _Sink();
    history = [];
    now = t0;
  });

  test('start publishes the first reading', () async {
    final sharer = make();
    source.next = fix(14.5, t0);
    sharer.start('u1', recordHistory: false);
    await pumpEventQueue();
    expect(sharer.isSharing, isTrue);
    expect(sink.published, hasLength(1));
    expect(sink.published.single.$1, 'u1');
    expect(history, isEmpty);
    sharer.stop();
  });

  test('a reading that has not moved is not written again', () async {
    final sharer = make();
    source.next = fix(14.5, t0);
    sharer.start('u1', recordHistory: false);
    await pumpEventQueue();
    now = t0.add(const Duration(seconds: 30));
    source.next = fix(14.50001, now);
    await sharer.poll();
    expect(sink.published, hasLength(1));
    sharer.stop();
  });

  test('the trail is recorded only with history consent', () async {
    final sharer = make();
    source.next = fix(14.5, t0);
    sharer.start('u1', recordHistory: true);
    await pumpEventQueue();
    expect(history, hasLength(1));

    // Consent withdrawn mid-session: same uid, new setting, no restart.
    sharer.start('u1', recordHistory: false);
    now = t0.add(const Duration(minutes: 1));
    source.next = fix(14.6, now);
    await sharer.poll();
    expect(sink.published, hasLength(2));
    expect(history, hasLength(1));
    sharer.stop();
  });

  test('nothing is read once stopped, or without permission', () async {
    final sharer = make();
    source.next = fix(14.5, t0);
    sharer.start('u1', recordHistory: false);
    await pumpEventQueue();
    expect(sink.published, hasLength(1));

    sharer.stop();
    await sharer.poll();
    expect(source.asked, 1);
    expect(sink.published, hasLength(1));

    source.availability_ = LocationAvailability.denied;
    sharer.start('u1', recordHistory: false);
    await pumpEventQueue();
    await sharer.poll();
    expect(source.asked, 1);
    expect(sink.published, hasLength(1));
    sharer.stop();
  });

  test('a failed write is tried again with the next reading', () async {
    final sharer = make();
    source.next = fix(14.5, t0);
    sink.failWith = StateError('offline');
    sharer.start('u1', recordHistory: false);
    await pumpEventQueue();
    expect(sink.published, isEmpty);

    // Back online, and the user has not moved. It must still go: the
    // guardian never got the first one.
    sink.failWith = null;
    now = t0.add(const Duration(seconds: 30));
    source.next = fix(14.5, now);
    await sharer.poll();
    expect(sink.published, hasLength(1));
    sharer.stop();
  });

  test('asks the OS once when permission is still askable', () async {
    final sharer = make();
    source.next = fix(14.5, t0);
    source.availability_ = LocationAvailability.denied;
    source.onRequest = LocationAvailability.ready;
    sharer.start('u1', recordHistory: false);
    await pumpEventQueue();
    expect(source.prompted, 1);
    expect(sink.published, hasLength(1));
    sharer.stop();
  });

  test('and not again once declined, nor ever when declined for good',
      () async {
    final sharer = make();
    source.next = fix(14.5, t0);
    source.availability_ = LocationAvailability.denied;
    sharer.start('u1', recordHistory: false);
    await pumpEventQueue();
    await sharer.poll();
    expect(source.prompted, 1);
    expect(sink.published, isEmpty);
    sharer.stop();

    source.availability_ = LocationAvailability.deniedForever;
    sharer.start('u1', recordHistory: false);
    await pumpEventQueue();
    expect(source.prompted, 1);
    sharer.stop();
  });

  test('forget clears the published point', () async {
    final sharer = make();
    await sharer.forget('u1');
    expect(sink.cleared, ['u1']);
  });
}
