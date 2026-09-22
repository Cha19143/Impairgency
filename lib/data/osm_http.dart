import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/navigation/map_services.dart';
import 'crash_reporting.dart';

/// Who is asking. Both services ask that an app name itself and give a way to
/// reach whoever runs it; the project's site is that, and it names no person.
const String kOsmUserAgent =
    'ImpairGency/0.1 (ph.impairgency.app; +https://impairgency-capstone.web.app)';

/// The free OpenStreetMap services, asked politely.
///
/// routing.openstreetmap.de and photon.komoot.io are run by volunteers and
/// cost nothing, and their terms are the price: an app that says who it is,
/// no more than about one request a second, and no hammering. So every
/// request carries [kOsmUserAgent], waits its turn per host, gives up after
/// [timeout], and a search asked twice in ten minutes is answered from memory.
///
/// Failures come back as [MapServiceException]s, named, never as raw socket
/// errors - what the person hears depends on which it was.
class OsmHttp {
  OsmHttp({
    http.Client? client,
    DateTime Function()? now,
    Future<void> Function(Duration delay)? wait,
    this.minGap = const Duration(milliseconds: 1100),
    this.timeout = const Duration(seconds: 8),
    this.cacheFor = const Duration(minutes: 10),
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _wait = wait ?? ((delay) => Future<void>.delayed(delay));

  final http.Client _client;
  final DateTime Function() _now;
  final Future<void> Function(Duration delay) _wait;

  /// Between two requests to the same host.
  final Duration minGap;
  final Duration timeout;
  final Duration cacheFor;

  /// When each host may next be asked.
  final Map<String, DateTime> _nextSlot = {};
  final Map<Uri, ({DateTime at, Object? json})> _cache = {};

  /// The JSON at [uri]. [cache] answers a repeat of the same request from
  /// memory - for searches, never for routes, which start wherever the person
  /// is now.
  ///
  /// [errorBody] reads a JSON error body before the status decides: OSRM says
  /// "NoRoute" with a 400.
  Future<Object?> getJson(Uri uri,
      {bool cache = false, bool errorBody = false}) async {
    try {
      return await _getJson(uri, cache: cache, errorBody: errorBody);
    } on MapServiceException catch (e, stack) {
      // Reported, not only said: a 403 or a 429 from a network in the
      // Philippines was invisible from here, and "the search is not working"
      // on a tester's phone could not be told from a bug.
      debugPrint('OSM ${uri.host} failed: ${e.failure} ${e.detail ?? ''}');
      crashRecorder.handled(e, stack, reason: 'OSM ${uri.host}');
      rethrow;
    }
  }

  Future<Object?> _getJson(Uri uri,
      {required bool cache, required bool errorBody}) async {
    final now = _now();
    if (cache) {
      final hit = _cache[uri];
      if (hit != null && now.difference(hit.at) < cacheFor) return hit.json;
    }

    // Take the next free slot for this host before waiting for it, so two
    // requests made together queue rather than both going at once.
    final slot = _nextSlot[uri.host];
    final start = slot == null || slot.isBefore(now) ? now : slot;
    _nextSlot[uri.host] = start.add(minGap);
    final delay = start.difference(now);
    if (delay > Duration.zero) await _wait(delay);

    final http.Response response;
    try {
      response = await _client.get(uri, headers: const {
        'User-Agent': kOsmUserAgent,
        'Accept': 'application/json',
      }).timeout(timeout);
    } on TimeoutException {
      throw const MapServiceException(MapServiceFailure.timeout);
    } on http.ClientException catch (e) {
      throw MapServiceException(MapServiceFailure.offline, e.message);
    } catch (e) {
      // SocketException and friends, which are not ClientExceptions on every
      // platform.
      debugPrint('OSM request failed: $e');
      throw MapServiceException(MapServiceFailure.offline, '$e');
    }

    if (response.statusCode == 429) {
      throw const MapServiceException(MapServiceFailure.busy, '429');
    }
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok && !(errorBody && response.statusCode < 500)) {
      throw MapServiceException(
          MapServiceFailure.unavailable, 'HTTP ${response.statusCode}');
    }

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw MapServiceException(MapServiceFailure.unavailable, e.message);
    }
    if (ok && cache) _cache[uri] = (at: _now(), json: json);
    return json;
  }

  void close() => _client.close();
}
