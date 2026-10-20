import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/navigation/navigation_history.dart';
import 'package:impairgency/data/navigation_history_repository.dart';
import 'package:impairgency/guardian/screens/navigation_history_screen.dart';

class _FakeHistory extends NavigationHistoryRepository {
  _FakeHistory(this.page);

  NavigationHistoryPage page;

  @override
  Stream<NavigationHistoryPage> watch({
    required String uid,
    required DateTime since,
    required int limit,
  }) async* {
    yield NavigationHistoryPage(
      entries: page.entries.take(limit).toList(),
      fetched: page.fetched < limit ? page.fetched : limit,
    );
  }
}

NavigationEntry _trip({
  required String id,
  required String name,
  required NavigationStatus status,
  required DateTime at,
  String address = 'Rizal Street, Malolos',
}) => NavigationEntry(
  id: id,
  destinationName: name,
  destinationAddress: address,
  destinationLat: 14.8,
  destinationLng: 120.9,
  originLat: 14.79,
  originLng: 120.92,
  startedAt: at,
  endedAt: status == NavigationStatus.ongoing ? null : at,
  status: status,
);

void main() {
  final now = DateTime(2026, 10, 15, 15, 42);

  Widget host(_FakeHistory history, {void Function(NavigationEntry)? onOpen}) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: NavigationHistoryScreen(
        uid: 'u1',
        repository: history,
        now: () => now,
        onOpen: onOpen ?? (_) {},
        onBack: () {},
      ),
    );
  }

  testWidgets('says so when there are no trips', (tester) async {
    await tester.pumpWidget(
      host(_FakeHistory(const NavigationHistoryPage(entries: [], fetched: 0))),
    );
    await tester.pump();
    expect(find.text('No navigation history yet.'), findsOneWidget);
    expect(find.text('Navigation history'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('lists a trip and filters by the status that is shown', (
    tester,
  ) async {
    NavigationEntry? opened;
    final history = _FakeHistory(
      NavigationHistoryPage(
        fetched: 3,
        entries: [
          _trip(
            id: 'done',
            name: 'Home',
            status: NavigationStatus.completed,
            at: now.subtract(const Duration(hours: 1)),
          ),
          _trip(
            id: 'stopped',
            name: 'Clinic',
            status: NavigationStatus.cancelled,
            at: now.subtract(const Duration(hours: 5)),
            address: '',
          ),
          _trip(
            id: 'stale',
            name: 'Market',
            status: NavigationStatus.ongoing,
            at: now.subtract(const Duration(hours: 3)),
          ),
        ],
      ),
    );
    await tester.pumpWidget(host(history, onOpen: (entry) => opened = entry));
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Rizal Street, Malolos'), findsWidgets);
    expect(find.text('Oct 15, 2026 - 2:42 PM'), findsOneWidget);
    // The filter and Home's chip.
    expect(find.text('Completed'), findsNWidgets(2));
    expect(find.text('Clinic'), findsOneWidget);
    // Written ongoing, but three hours old: shown as cancelled, along with
    // Clinic. The filter chip is the third "Cancelled".
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Cancelled'), findsNWidgets(3));
    expect(find.text('Ongoing'), findsNothing);

    await tester.tap(find.text('Completed').first);
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Clinic'), findsNothing);
    expect(find.text('Market'), findsNothing);

    await tester.tap(find.text('Cancelled').first);
    await tester.pump();
    expect(find.text('Home'), findsNothing);
    expect(find.text('Clinic'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.tap(find.text('Home'));
    expect(opened?.id, 'done');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a filter that matches nothing says so', (tester) async {
    await tester.pumpWidget(
      host(
        _FakeHistory(
          NavigationHistoryPage(
            fetched: 1,
            entries: [
              _trip(
                id: 'done',
                name: 'Home',
                status: NavigationStatus.completed,
                at: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Cancelled'));
    await tester.pump();
    expect(find.text('No results for this filter.'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
