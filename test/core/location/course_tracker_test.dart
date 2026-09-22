import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:impairgency/core/location/course_tracker.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/data/geolocator_location_source.dart';

void main() {
  final start = DateTime.utc(2026, 9, 18, 10);

  LocationFix fix(double lat, double lng,
          {int seconds = 0, double? heading, double? speed}) =>
      LocationFix(
        latitude: lat,
        longitude: lng,
        accuracyMetres: 5,
        at: start.add(Duration(seconds: seconds)),
        headingDegrees: heading,
        speedMetresPerSecond: speed,
      );

  group('a course from the walk, when the phone gives none', () {
    test('walking east is east', () {
      final t = CourseTracker();
      t.withCourse(fix(14.79, 120.9200));
      final next = t.withCourse(fix(14.79, 120.9201, seconds: 5)); // ~11 m
      expect(next.headingDegrees, closeTo(90, 1));
      expect(next.speedMetresPerSecond, closeTo(2.2, 0.3));
      expect(next.usableHeading, isNotNull);
    });

    test('a few metres of wander standing still says nothing', () {
      final t = CourseTracker();
      t.withCourse(fix(14.79, 120.92));
      final next = t.withCourse(fix(14.79001, 120.92, seconds: 2)); // ~1 m
      expect(next.headingDegrees, isNull);
    });

    test('readings too far apart in time are not one walk', () {
      final t = CourseTracker();
      t.withCourse(fix(14.79, 120.9200));
      final next = t.withCourse(fix(14.79, 120.9201, seconds: 60));
      expect(next.headingDegrees, isNull);
    });

    test("the phone's own course is kept", () {
      final t = CourseTracker();
      t.withCourse(fix(14.79, 120.9200));
      final next = t.withCourse(
          fix(14.79, 120.9201, seconds: 5, heading: 80, speed: 1.4));
      expect(next.headingDegrees, 80);
      expect(next.speedMetresPerSecond, 1.4);
    });
  });

  group('readings from the platform', () {
    Position position({required bool hasHeading, required bool hasSpeed}) =>
        Position(
          latitude: 14.79,
          longitude: 120.92,
          timestamp: start,
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
          hasHeading: hasHeading,
          hasSpeed: hasSpeed,
        );

    test('a course the phone did not report is not due north', () {
      final f = fixFromPosition(position(hasHeading: false, hasSpeed: false));
      expect(f.headingDegrees, isNull);
      expect(f.speedMetresPerSecond, isNull);
    });

    test('one it did report is kept', () {
      final f = fixFromPosition(position(hasHeading: true, hasSpeed: true));
      expect(f.headingDegrees, 0);
      expect(f.speedMetresPerSecond, 0);
    });
  });
}
