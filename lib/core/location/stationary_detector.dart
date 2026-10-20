/// Tells when someone has stayed in one place for too long.
///
/// Fed every reading the sharer takes. Says yes once per stay.
///
/// Phone test: in this file, set [kStationaryAfter] to `Duration(minutes: 2)`
/// and, if you want a tighter spot, [kStationaryRadiusMetres]. Set them back
/// to `Duration(hours: 1)` and `30` before a real walk.
library;

import '../navigation/destination.dart';
import '../places/journey.dart' show kMaxUsefulAccuracyMetres;
import 'location_fix.dart';
import 'location_sharing.dart' show metresBetween;

/// How long someone must stay inside [kStationaryRadiusMetres].
///
/// Set this to `Duration(minutes: 2)` for a phone test, then set it back
/// to `Duration(hours: 1)`.
const Duration kStationaryAfter = Duration(hours: 1);

/// Drift smaller than this is GPS wander, not the person leaving.
///
/// Set this back to `30` after a phone test.
const double kStationaryRadiusMetres = 30;

/// A saved Home within this of the reading counts as being at home.
const double kHomeMatchRadiusMetres = 80;

class StationaryDetector {
  StationaryDetector({
    this.radiusMetres = kStationaryRadiusMetres,
    this.after = kStationaryAfter,
    this.maxGap = const Duration(minutes: 10),
    this.maxAccuracyMetres = kMaxUsefulAccuracyMetres,
  });

  /// Gumalaw lang nang higit dito ang bilang na "umalis".
  final double radiusMetres;

  /// Gaano katagal bago mag-alert.
  final Duration after;

  /// Kapag mas matagal kaysa dito ang pagitan ng dalawang reading, hindi
  /// natin alam kung ano ang nangyari sa pagitan (sarado ang app), kaya
  /// nagsisimula ulit ang bilang.
  final Duration maxGap;

  final double maxAccuracyMetres;

  LocationFix? _anchor;
  DateTime? _lastAt;
  bool _alerted = false;

  /// True isang beses lang bawat pagtigil. Hindi nag-a-alert kung [atHome].
  bool note(LocationFix fix, {bool atHome = false}) {
    if (fix.accuracyMetres > maxAccuracyMetres) return false;

    final anchor = _anchor;
    final last = _lastAt;
    _lastAt = fix.at;

    final gapped = last != null && fix.at.difference(last) > maxGap;
    if (anchor == null || gapped || metresBetween(anchor, fix) > radiusMetres) {
      _anchor = fix;
      _alerted = false;
      return false;
    }

    if (atHome || _alerted) return false;
    if (fix.at.difference(anchor.at) >= after) {
      _alerted = true;
      return true;
    }
    return false;
  }

  /// Para sa alert na hindi naipadala: subukan ulit sa susunod na reading.
  void rearm() => _alerted = false;

  void reset() {
    _anchor = null;
    _lastAt = null;
    _alerted = false;
  }
}

/// Home, Work and School use the kind as the document id. A place the user
/// named "Home" counts too.
bool isSavedHome(Destination place) =>
    place.kind == DestinationKind.home ||
    place.id == DestinationKind.home.name ||
    place.label.trim().toLowerCase() == 'home';

/// True when [fix] is within [kHomeMatchRadiusMetres] of a saved Home.
bool isAtSavedHome(LocationFix fix, Iterable<Destination> places) {
  for (final place in places) {
    if (!isSavedHome(place)) continue;
    final there = LocationFix(
      latitude: place.latitude,
      longitude: place.longitude,
      accuracyMetres: 0,
      at: fix.at,
    );
    if (metresBetween(fix, there) <= kHomeMatchRadiusMetres) return true;
  }
  return false;
}
