import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/navigation/navigation_history.dart';
import 'package:impairgency/data/navigation_history_repository.dart';
import 'package:impairgency/data/navigation_history_writer.dart';

const home = Destination(
  id: 'home',
  label: 'Home',
  latitude: 14.8,
  longitude: 120.9,
  address: 'Rizal Street',
);
const clinic = Destination(
  id: 'clinic',
  label: 'Clinic',
  latitude: 14.81,
  longitude: 120.91,
);

final fix = LocationFix(
  latitude: 14.79,
  longitude: 120.92,
  accuracyMetres: 8,
  at: DateTime(2026, 10, 15, 13),
);

class FakeSink implements NavigationHistorySink {
  var _ids = 0;
  final starts = <String>[];
  final finishes = <({String id, String status})>[];

  /// When set, [start] waits on it after recording the call.
  Completer<void>? gate;

  @override
  String newId(String uid) => 'e${++_ids}';

  @override
  Future<void> start({
    required String uid,
    required String entryId,
    required Destination destination,
    required double originLat,
    required double originLng,
  }) async {
    starts.add(entryId);
    final waiting = gate;
    if (waiting != null) await waiting.future;
  }

  @override
  Future<void> finish({
    required String uid,
    required String entryId,
    required String status,
  }) async {
    finishes.add((id: entryId, status: status));
  }
}

void main() {
  late FakeSink sink;
  late NavigationHistoryWriter writer;

  setUp(() {
    sink = FakeSink();
    writer = NavigationHistoryWriter(sink);
  });

  test('the first position opens one row; later positions do not', () async {
    writer.begin(uid: 'u', destination: home);
    writer.notePosition(fix);
    writer.notePosition(fix);
    await pumpEventQueue();
    expect(sink.starts, ['e1']);
    expect(sink.finishes, isEmpty);
  });

  test('the same destination again is not a new trip', () async {
    writer.begin(uid: 'u', destination: home);
    writer.notePosition(fix);
    writer.begin(uid: 'u', destination: home);
    writer.notePosition(fix);
    await pumpEventQueue();
    expect(sink.starts, ['e1']);
    expect(sink.finishes, isEmpty);
  });

  test('arriving closes the row, and leaving afterwards does not', () async {
    writer.begin(uid: 'u', destination: home);
    writer.notePosition(fix);
    await pumpEventQueue();
    await writer.complete();
    await writer.cancel();
    expect(sink.finishes, [(id: 'e1', status: 'completed')]);
  });

  test('leaving before arriving cancels the row', () async {
    writer.begin(uid: 'u', destination: home);
    writer.notePosition(fix);
    await pumpEventQueue();
    await writer.cancel();
    expect(sink.finishes, [(id: 'e1', status: 'cancelled')]);
  });

  test('leaving before any position writes nothing', () async {
    writer.begin(uid: 'u', destination: home);
    await writer.cancel();
    writer.notePosition(fix);
    await pumpEventQueue();
    expect(sink.starts, isEmpty);
    expect(sink.finishes, isEmpty);
  });

  test('a new destination cancels the open trip', () async {
    writer.begin(uid: 'u', destination: home);
    writer.notePosition(fix);
    await pumpEventQueue();
    writer.begin(uid: 'u', destination: clinic);
    writer.notePosition(fix);
    await pumpEventQueue();
    expect(sink.starts, ['e1', 'e2']);
    expect(sink.finishes, [
      (id: 'e1', status: NavigationStatus.cancelled.name),
    ]);
  });

  test('a create still in flight is closed with the ending that won', () async {
    sink.gate = Completer<void>();
    writer.begin(uid: 'u', destination: home);
    writer.notePosition(fix);
    await pumpEventQueue();
    expect(sink.starts, ['e1']);

    final ending = writer.cancel();
    sink.gate!.complete();
    await ending;
    await pumpEventQueue();

    expect(sink.finishes, isNotEmpty);
    expect(sink.finishes.every((f) => f.status == 'cancelled'), isTrue);
    expect(sink.finishes.map((f) => f.id).toSet(), {'e1'});
  });
}
