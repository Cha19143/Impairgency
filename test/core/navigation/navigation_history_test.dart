import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/navigation/navigation_history.dart';

void main() {
  final started = DateTime(2026, 10, 15, 13, 42);

  NavigationEntry trip({
    NavigationStatus status = NavigationStatus.ongoing,
    DateTime? at,
  }) => NavigationEntry(
    id: 'e1',
    destinationName: 'Home',
    destinationAddress: 'Rizal Street',
    destinationLat: 14.8,
    destinationLng: 120.9,
    originLat: 14.79,
    originLng: 120.92,
    startedAt: at ?? started,
    endedAt: null,
    status: status,
  );

  test('a time reads as month, day, year, then the clock', () {
    expect(formatNavigationWhen(started), 'Oct 15, 2026 - 1:42 PM');
    expect(
      formatNavigationWhen(DateTime(2026, 10, 15, 0, 5)),
      'Oct 15, 2026 - 12:05 AM',
    );
    expect(
      formatNavigationWhen(DateTime(2026, 10, 15, 12)),
      'Oct 15, 2026 - 12:00 PM',
    );
  });

  test('an ongoing trip older than two hours is shown as cancelled', () {
    final entry = trip();
    expect(
      entry.displayStatus(started.add(const Duration(hours: 2))),
      NavigationStatus.ongoing,
    );
    expect(
      entry.displayStatus(started.add(const Duration(hours: 2, seconds: 1))),
      NavigationStatus.cancelled,
    );
    expect(
      entry.displayStatus(started.add(const Duration(minutes: 10))),
      NavigationStatus.ongoing,
    );
  });

  test('a finished trip keeps the status that was written', () {
    final done = trip(status: NavigationStatus.completed);
    expect(
      done.displayStatus(started.add(const Duration(days: 3))),
      NavigationStatus.completed,
    );
    final stopped = trip(status: NavigationStatus.cancelled);
    expect(stopped.displayStatus(started), NavigationStatus.cancelled);
  });

  test('status filters use the status that is shown', () {
    final fresh = trip();
    final stale = trip(at: started.subtract(const Duration(hours: 3)));
    final done = trip(status: NavigationStatus.completed);
    final now = started;

    expect(fresh.matchesFilter(NavigationStatusFilter.all, now), isTrue);
    expect(fresh.matchesFilter(NavigationStatusFilter.completed, now), isFalse);
    expect(fresh.matchesFilter(NavigationStatusFilter.cancelled, now), isFalse);

    expect(stale.matchesFilter(NavigationStatusFilter.cancelled, now), isTrue);
    expect(stale.matchesFilter(NavigationStatusFilter.completed, now), isFalse);
    expect(done.matchesFilter(NavigationStatusFilter.completed, now), isTrue);
    expect(done.matchesFilter(NavigationStatusFilter.cancelled, now), isFalse);
  });

  test(
    'an empty last-30-days list is no history; a narrower miss is the filter',
    () {
      expect(
        navigationHistoryEmptyMessage(
          loading: false,
          hasError: false,
          fetched: 0,
          visible: 0,
          date: NavigationDateFilter.last30Days,
        ),
        'No navigation history yet.',
      );
      expect(
        navigationHistoryEmptyMessage(
          loading: false,
          hasError: false,
          fetched: 0,
          visible: 0,
          date: NavigationDateFilter.today,
        ),
        'No results for this filter.',
      );
      expect(
        navigationHistoryEmptyMessage(
          loading: false,
          hasError: false,
          fetched: 4,
          visible: 0,
          date: NavigationDateFilter.last30Days,
        ),
        'No results for this filter.',
      );
      expect(
        navigationHistoryEmptyMessage(
          loading: true,
          hasError: false,
          fetched: 0,
          visible: 0,
          date: NavigationDateFilter.last30Days,
        ),
        isNull,
      );
    },
  );

  test('today starts at local midnight; a week and a month roll back', () {
    final now = DateTime(2026, 10, 15, 15, 42);
    expect(
      navigationRangeStart(NavigationDateFilter.today, now),
      DateTime(2026, 10, 15),
    );
    expect(
      navigationRangeStart(NavigationDateFilter.last7Days, now),
      now.subtract(const Duration(days: 7)),
    );
    expect(
      navigationRangeStart(NavigationDateFilter.last30Days, now),
      now.subtract(kNavigationRetention),
    );
  });
}
