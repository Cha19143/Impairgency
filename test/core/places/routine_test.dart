import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/places/place.dart';
import 'package:impairgency/core/places/routine.dart';
import 'package:impairgency/core/places/stay.dart';

/// A visit arriving at [hour]:[minute] local on a given date, lasting [hours].
Stay visit({
  required int year,
  required int month,
  required int dayOfMonth,
  required int hour,
  int minute = 0,
  int hours = 8,
}) {
  final arrived = DateTime.utc(year, month, dayOfMonth, hour, minute);
  return Stay(
    latitude: 14.7942,
    longitude: 120.9214,
    arrived: arrived,
    departed: arrived.add(Duration(hours: hours)),
    fixCount: 30,
  );
}

Place placeOf(List<Stay> visits, {String? label}) =>
    Place(latitude: 14.7942, longitude: 120.9214, visits: visits, label: label);

void main() {
  // 1-5 September 2026 is Tuesday to Saturday.
  Stay weekday(int dayOfMonth, {int hour = 8, int minute = 0, int hours = 8}) =>
      visit(
          year: 2026,
          month: 9,
          dayOfMonth: dayOfMonth,
          hour: hour,
          minute: minute,
          hours: hours);

  group('refusing to claim a pattern it cannot support', () {
    test('two visits is a coincidence, not a routine', () {
      expect(routineOf(placeOf([weekday(1), weekday(2)])), isNull);
      expect(describeRoutine(placeOf([weekday(1), weekday(2)])), isNull);
    });

    test('four visits is enough to look at', () {
      expect(routineOf(placeOf([for (var d = 1; d <= 4; d++) weekday(d)])),
          isNotNull);
    });

    test('a scattered arrival time has no typical time', () {
      // 7am, 1pm, 7pm, 11pm. The median is early afternoon and means nothing.
      final place = placeOf([
        weekday(1, hour: 7),
        weekday(2, hour: 13),
        weekday(3, hour: 19),
        weekday(4, hour: 23),
      ]);
      final routine = routineOf(place)!;

      expect(routine.hasTypicalTime, isFalse);
      expect(describeRoutine(place), contains('not at a regular time'));
      expect(describeRoutine(place), contains('4 times'));
    });

    test('a tight arrival time does have one', () {
      final place = placeOf([
        weekday(1, hour: 7, minute: 25),
        weekday(2, hour: 7, minute: 40),
        weekday(3, hour: 7, minute: 30),
        weekday(4, hour: 7, minute: 35),
      ]);
      final routine = routineOf(place)!;

      expect(routine.hasTypicalTime, isTrue);
      expect(routine.typicalArrival, inInclusiveRange(7 * 60 + 25, 7 * 60 + 40));
    });

    test('one late night does not move the typical time much', () {
      // The median is what makes this hold; a mean would drag it two hours.
      final place = placeOf([
        weekday(1, hour: 8),
        weekday(2, hour: 8, minute: 10),
        weekday(3, hour: 8, minute: 5),
        weekday(4, hour: 8, minute: 15),
        weekday(5, hour: 8, minute: 20),
      ]);
      final routine = routineOf(place)!;
      expect(routine.typicalArrival, inInclusiveRange(8 * 60, 8 * 60 + 20));
    });
  });

  group('local time', () {
    test('a routine described in UTC would be wrong by hours', () {
      // 23:30 UTC is 07:30 the next morning in Manila.
      final place = placeOf([
        for (var d = 1; d <= 5; d++) weekday(d, hour: 23, minute: 30),
      ]);

      final utc = routineOf(place)!;
      expect(utc.typicalArrival, 23 * 60 + 30);

      final manila = routineOf(place, offset: const Duration(hours: 8))!;
      expect(manila.typicalArrival, 7 * 60 + 30);
    });

    test('the offset also moves the weekday', () {
      // Saturday 23:00 UTC is Sunday morning locally.
      final saturdayNight = placeOf([
        for (var d = 0; d < 5; d++)
          visit(year: 2026, month: 9, dayOfMonth: 5 + d * 7, hour: 23),
      ]);
      expect(routineOf(saturdayNight)!.weekdays, {6});
      expect(routineOf(saturdayNight, offset: const Duration(hours: 8))!.weekdays,
          {7});
    });
  });

  group('weekday and weekend patterns', () {
    test('five straight weekdays reads as a workweek pattern', () {
      // 31 Aug 2026 is a Monday.
      final place = placeOf([
        for (var d = 0; d < 5; d++)
          visit(year: 2026, month: 8, dayOfMonth: 31 + d, hour: 8),
      ]);
      final routine = routineOf(place)!;

      expect(routine.weekdays, {1, 2, 3, 4, 5});
      expect(routine.isWorkweekPattern, isTrue);
      expect(routine.isWeekendPattern, isFalse);
      expect(describeRoutine(place), contains('on weekdays'));
    });

    test('a single weekday visit among others is not a workweek pattern', () {
      final place = placeOf([
        for (var d = 0; d < 4; d++)
          visit(year: 2026, month: 8, dayOfMonth: 31 + d, hour: 8),
        visit(year: 2026, month: 9, dayOfMonth: 5, hour: 8), // Saturday
      ]);
      expect(routineOf(place)!.isWorkweekPattern, isFalse);
    });

    test('Sundays read as a weekend pattern', () {
      final place = placeOf([
        for (var d = 0; d < 4; d++)
          visit(year: 2026, month: 9, dayOfMonth: 6 + d * 7, hour: 9),
      ]);
      final routine = routineOf(place)!;
      expect(routine.weekdays, {7});
      expect(routine.isWeekendPattern, isTrue);
      expect(describeRoutine(place), contains('at weekends'));
    });
  });

  group('what it actually says', () {
    test('uses the name the user gave the place', () {
      final place = placeOf(
          [for (var d = 1; d <= 5; d++) weekday(d, hour: 8)],
          label: 'the clinic');
      expect(describeRoutine(place), contains('arrive the clinic around'));
    });

    test('says "here" when the place has no name', () {
      final place = placeOf([for (var d = 1; d <= 5; d++) weekday(d, hour: 8)]);
      expect(describeRoutine(place), contains('arrive here around'));
    });

    test('reports the visit count, so the claim can be judged', () {
      final place = placeOf([for (var d = 1; d <= 6; d++) weekday(d, hour: 8)]);
      expect(describeRoutine(place), contains('6 visits so far'));
    });

    test('never claims to have learned or predicted anything', () {
      final place = placeOf([for (var d = 1; d <= 6; d++) weekday(d, hour: 8)]);
      final text = describeRoutine(place)!.toLowerCase();
      for (final overclaim in ['learn', 'predict', 'ai ', 'we know', 'always']) {
        expect(text, isNot(contains(overclaim)), reason: overclaim);
      }
    });
  });

  group('clock wording', () {
    test('reads the way a person would say it', () {
      expect(clockTime(7 * 60 + 30), '7:30 in the morning');
      expect(clockTime(8 * 60), '8 in the morning');
      expect(clockTime(12 * 60), '12 in the afternoon');
      expect(clockTime(13 * 60 + 5), '1:05 in the afternoon');
      expect(clockTime(19 * 60 + 45), '7:45 in the evening');
      expect(clockTime(0), '12 in the morning');
    });

    test('pads single-digit minutes', () {
      expect(clockTime(9 * 60 + 5), contains(':05'));
    });
  });
}
