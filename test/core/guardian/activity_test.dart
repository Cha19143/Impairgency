import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/guardian/activity.dart';

/// The rows behind the guardian's "recent activity".
void main() {
  final t0 = DateTime.utc(2026, 9, 13, 9);

  group('headline', () {
    test('keeps a short detail as it is', () {
      expect(ActivityEvent.headline('chair'), 'chair');
    });

    test('takes the first line of a page and trims it', () {
      expect(
        ActivityEvent.headline('  MEDICINE\nTake one tablet daily\nKeep dry'),
        'MEDICINE',
      );
    });

    test('cuts a long line to sixty characters with an ellipsis', () {
      final long = 'A' * 100;
      final h = ActivityEvent.headline(long);
      expect(h.length, ActivityEvent.maxDetailLength);
      expect(h, endsWith('…'));
    });
  });

  group('describe', () {
    test('names the kind and the age', () {
      final e = ActivityEvent(
          kind: ActivityKind.obstacle,
          detail: 'chair',
          at: t0.subtract(const Duration(minutes: 2)));
      expect(activityHeadline(e), 'Obstacle: chair');
      expect(describeActivity(e, now: t0), startsWith('Obstacle: chair, '));
      expect(describeActivity(e, now: t0), contains('2 min'));
    });

    test('text and journeys read naturally', () {
      expect(
        activityHeadline(ActivityEvent(
            kind: ActivityKind.textRead, detail: 'MEDICINE', at: t0)),
        'Read: MEDICINE',
      );
      expect(
        activityHeadline(
            ActivityEvent(kind: ActivityKind.journey, detail: 'Work', at: t0)),
        'Set off for Work',
      );
    });
  });

  group('json', () {
    test('round-trips, and rejects what it does not know', () {
      final e =
          ActivityEvent(kind: ActivityKind.textRead, detail: 'Hello', at: t0);
      final back = ActivityEvent.fromJson(e.toJson(), t0)!;
      expect(back.kind, ActivityKind.textRead);
      expect(back.detail, 'Hello');
      expect(back.at, t0);
      expect(ActivityEvent.fromJson({'kind': 'dance', 'detail': 'x'}, t0),
          isNull);
      expect(ActivityEvent.fromJson({'kind': 'obstacle'}, t0), isNull);
    });
  });

  group('throttle', () {
    test('one row per object per minute, case-insensitively', () {
      final t = ActivityThrottle();
      expect(t.admit(ActivityKind.obstacle, 'chair', t0), isTrue);
      expect(
          t.admit(ActivityKind.obstacle, 'Chair',
              t0.add(const Duration(seconds: 30))),
          isFalse);
      expect(t.admit(ActivityKind.obstacle, 'car', t0), isTrue);
      expect(
          t.admit(ActivityKind.obstacle, 'chair',
              t0.add(const Duration(minutes: 1))),
          isTrue);
    });

    test('kinds do not share a key', () {
      final t = ActivityThrottle();
      expect(t.admit(ActivityKind.obstacle, 'Work', t0), isTrue);
      expect(t.admit(ActivityKind.journey, 'Work', t0), isTrue);
    });
  });
}
