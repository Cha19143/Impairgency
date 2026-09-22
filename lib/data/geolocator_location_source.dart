import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart';

import '../core/location/location_fix.dart';
import '../core/location/location_source.dart';

/// [LocationSource] backed by the platform.
///
/// Everything here that can fail, fails quietly and returns a state rather than
/// throwing. An SOS must not be taken down by a permission prompt.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  LocationFix _toFix(Position p) => fixFromPosition(p);

  /// Readings as the user moves, for turn-by-turn guidance.
  ///
  /// Every reading, every two seconds on Android. It used to be only after
  /// two metres of movement, so someone standing still got no readings, and
  /// after thirty seconds was told their position was lost. Errors reach the
  /// screen, which says them; a refused permission ends the stream before it
  /// starts.
  Stream<LocationFix> positions() async* {
    if (await availability() != LocationAvailability.ready) return;
    final settings = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 2),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
          );
    yield* Geolocator.getPositionStream(locationSettings: settings)
        .map(_toFix);
  }

  LocationAvailability _map(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse =>
          LocationAvailability.ready,
        LocationPermission.deniedForever => LocationAvailability.deniedForever,
        // `unableToDetermine` is treated as askable rather than blocked: the
        // recoverable reading is the safer wrong answer here.
        LocationPermission.denied ||
        LocationPermission.unableToDetermine =>
          LocationAvailability.denied,
      };

  Future<LocationAvailability> _withServiceCheck(
      LocationAvailability permissionState) async {
    if (permissionState != LocationAvailability.ready) return permissionState;
    final enabled = await Geolocator.isLocationServiceEnabled();
    return enabled
        ? LocationAvailability.ready
        : LocationAvailability.serviceDisabled;
  }

  @override
  Future<LocationAvailability> availability() async {
    try {
      return await _withServiceCheck(_map(await Geolocator.checkPermission()));
    } catch (_) {
      return LocationAvailability.denied;
    }
  }

  @override
  Future<LocationAvailability> requestPermission() async {
    try {
      final current = _map(await Geolocator.checkPermission());
      // Asking again after a permanent refusal does nothing on either platform
      // and, on iOS, cannot even show a prompt. Report it rather than pretend.
      if (current == LocationAvailability.deniedForever) return current;
      return await _withServiceCheck(_map(await Geolocator.requestPermission()));
    } catch (_) {
      return LocationAvailability.denied;
    }
  }

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (await availability() != LocationAvailability.ready) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return _toFix(position);
    } catch (_) {
      // Timeouts are the common case indoors. The caller falls back to
      // lastKnownFix, which is why this returns null rather than rethrowing.
      return null;
    }
  }

  @override
  Future<LocationFix?> lastKnownFix() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      return position == null ? null : _toFix(position);
    } catch (_) {
      return null;
    }
  }
}

/// Obtains the best fix available inside [timeout], falling back to whatever
/// the platform already remembered.
///
/// This is the call SOS makes. It never waits longer than [timeout], because
/// the alarm and the phone call must not queue behind a satellite.
Future<LocationFix?> bestEffortFix(
  LocationSource source, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final fresh = await source.currentFix(timeout: timeout);
  if (fresh != null) return fresh;
  return source.lastKnownFix();
}

/// [p] as the app's own reading. A course or a speed the platform did not
/// report is null, not 0.0: a missing heading used to arrive as due north.
LocationFix fixFromPosition(Position p) => LocationFix(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyMetres: p.accuracy,
      at: p.timestamp,
      headingDegrees: p.hasHeading ? p.heading : null,
      speedMetresPerSecond: p.hasSpeed ? p.speed : null,
    );
