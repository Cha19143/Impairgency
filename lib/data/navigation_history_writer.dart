import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/location/location_fix.dart';
import '../core/navigation/destination.dart';
import '../core/navigation/navigation_history.dart';
import 'navigation_history_repository.dart';

/// Opens one history row per trip and closes it when the trip ends.
///
/// The row is created on the first position, because that position is the
/// origin and the rules require it at creation. A screen rebuild does not
/// open a second row: the id is remembered until the trip ends. Everything
/// is fire-and-forget. A failure is logged and directions carry on, including
/// with no connection.
class NavigationHistoryWriter {
  NavigationHistoryWriter(this._sink);

  final NavigationHistorySink _sink;

  int _generation = 0;
  bool _open = false;
  String? _terminal;
  String? _uid;
  String? _entryId;
  Destination? _destination;

  /// Starts a trip to [destination]. The same destination again, while the
  /// trip is still open, is ignored — that is a rebuild, not a new trip.
  /// A different destination cancels the one in progress.
  void begin({required String uid, required Destination destination}) {
    if (_open &&
        _terminal == null &&
        _uid == uid &&
        _destination?.id == destination.id) {
      return;
    }
    final previousUid = _uid;
    final previousId = (_open && _terminal == null) ? _entryId : null;
    _generation++;
    _uid = uid;
    _destination = destination;
    _entryId = null;
    _open = true;
    _terminal = null;
    if (previousId != null && previousUid != null) {
      unawaited(
        _close(previousUid, previousId, NavigationStatus.cancelled.name),
      );
    }
  }

  /// The first position of the open trip becomes its origin. Later positions
  /// are ignored.
  void notePosition(LocationFix fix) {
    if (!_open || _terminal != null || _entryId != null) return;
    final uid = _uid;
    final destination = _destination;
    if (uid == null || destination == null) return;
    final generation = _generation;
    final String id;
    try {
      id = _sink.newId(uid);
    } catch (e) {
      debugPrint('navigation history start failed: $e');
      return;
    }
    _entryId = id;
    unawaited(
      _start(
        generation: generation,
        uid: uid,
        id: id,
        destination: destination,
        fix: fix,
      ),
    );
  }

  /// The user reached the destination. A later cancel does not overwrite it.
  Future<void> complete() => _end(NavigationStatus.completed.name);

  /// The user left before arriving, or the screen went away while the trip
  /// was still open. No effect once the trip has already ended.
  Future<void> cancel() => _end(NavigationStatus.cancelled.name);

  Future<void> _end(String status) async {
    if (!_open || _terminal != null) return;
    final uid = _uid;
    final id = _entryId;
    _terminal = status;
    _open = false;
    // No position yet: nothing was written. An in-flight create sees
    // [_terminal] and closes the row itself once the create lands.
    if (uid == null || id == null) return;
    await _close(uid, id, status);
  }

  Future<void> _start({
    required int generation,
    required String uid,
    required String id,
    required Destination destination,
    required LocationFix fix,
  }) async {
    try {
      await _sink.start(
        uid: uid,
        entryId: id,
        destination: destination,
        originLat: fix.latitude,
        originLng: fix.longitude,
      );
      if (generation != _generation) {
        await _close(uid, id, NavigationStatus.cancelled.name);
        return;
      }
      final terminal = _terminal;
      if (terminal != null) {
        await _close(uid, id, terminal);
      }
    } catch (e) {
      debugPrint('navigation history start failed: $e');
    }
  }

  Future<void> _close(String uid, String id, String status) async {
    try {
      await _sink.finish(uid: uid, entryId: id, status: status);
    } catch (e) {
      debugPrint('navigation history $status failed: $e');
    }
  }
}
