/// What "where am I" says.
///
/// It used to read back the SOS receipt's sentence, so someone who had only
/// asked a question heard "Your location was sent." Nothing had been sent, and
/// the sentence named no place. This answers the question that was asked,
/// with the quality of the answer in it: how old the position is, how rough,
/// and how far it is from the places the user has saved.
///
/// Pure, so each wording is tested without a satellite.
library;

import '../navigation/destination.dart';
import '../navigation/guidance.dart';
import '../places/geo.dart';
import 'location_fix.dart';
import 'location_policy.dart';

/// Saved places further away than this are not a useful reference point.
const double kNearbyPlaceMetres = 2000;

/// [nearby] is what the map says is at the position - "near Rizal Street,
/// Malolos" - when it could be asked. A position too rough to place is never
/// given a street.
String whereAmISentence({
  required LocationFix fix,
  required DateTime now,
  List<Destination> places = const [],
  String? nearby,
}) {
  final age = fix.ageAt(now);
  final prefix = age > kFreshEnough
      ? 'I could not get a new position. The last one, from '
          '${describeAge(age)}: '
      : '';

  if (fix.accuracyMetres > kVagueAccuracyMetres) {
    return '${prefix}I only have a rough position, accurate to about '
        '${(fix.accuracyMetres / 100).round() * 100} metres, so I cannot say '
        'where you are.';
  }

  Destination? nearest;
  var nearestMetres = double.infinity;
  for (final place in places) {
    final d = metresBetween(
        fix.latitude, fix.longitude, place.latitude, place.longitude);
    if (d < nearestMetres) {
      nearest = place;
      nearestMetres = d;
    }
  }

  final accuracy = 'accurate to about ${_roundAccuracy(fix.accuracyMetres)} '
      'metres';

  if (nearest != null && nearestMetres <= kNearbyPlaceMetres) {
    final here = nearestMetres <=
        (fix.accuracyMetres * 0.8 > kArrivedMetres
            ? fix.accuracyMetres * 0.8
            : kArrivedMetres);
    final where = here
        ? 'You are at ${nearest.label}'
        : 'You are ${describeDistance(nearestMetres)} from ${nearest.label}'
            '${nearby == null ? '' : ', $nearby'}';
    return '$prefix$where, $accuracy.';
  }

  if (nearby != null) return '${prefix}You are $nearby, $accuracy.';
  return '${prefix}I have your position, $accuracy, but no place you have '
      'saved is nearby, and I cannot name the street.';
}

int _roundAccuracy(double metres) =>
    metres < 10 ? 10 : (metres / 10).round() * 10;
