/// Tells when someone has stayed in one place for too long.
///
/// Fed every reading the sharer takes. Says yes once per stay.
library;

import '../places/journey.dart' show kMaxUsefulAccuracyMetres;
import 'location_fix.dart';
import 'location_sharing.dart' show metresBetween;

class StationaryDetector {
  StationaryDetector({
    this.radiusMetres = 50,
    this.after = const Duration(hours: 1),
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