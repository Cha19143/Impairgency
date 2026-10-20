import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/guardian/obstacle_event.dart';
import 'package:impairgency/data/obstacle_history_repository.dart';
import 'package:impairgency/guardian/screens/obstacle_history_screen.dart';

class _FakeHistory extends ObstacleHistoryRepository {
  _FakeHistory(this.page);

  ObstacleHistoryPage page;

  @override
  Stream<ObstacleHistoryPage> watch({
    required String uid,
    required DateTime since,
    required int limit,
  }) async* {
    yield ObstacleHistoryPage(
      entries: page.entries.take(limit).toList(),
      fetched: page.fetched < limit ? page.fetched : limit,
    );
  }
}

ObstacleSighting _row({
  required String id,
  required String type,
  required DateTime at,
}) =>
    ObstacleSighting(
      id: id,
      type: type,
      at: at,
      latitude: 14.84,
      longitude: 120.81,
      distanceMetres: 1.5,
      distanceApproximate: true,
    );

void main() {
  final now = DateTime(2026, 10, 20, 16, 5);

  Widget host(_FakeHistory history) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: ObstacleHistoryScreen(
        uid: 'u1',
        repository: history,
        now: () => now,
        onBack: () {},
      ),
    );
  }

  testWidgets('says so when there are no obstacles', (tester) async {
    await tester.pumpWidget(
      host(_FakeHistory(const ObstacleHistoryPage(entries: [], fetched: 0))),
    );
    await tester.pump();
    expect(find.text('No obstacle history yet.'), findsOneWidget);
    expect(find.text('Obstacle history'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('lists type, time, location and distance, and filters by type',
      (tester) async {
    final history = _FakeHistory(ObstacleHistoryPage(
      fetched: 2,
      entries: [
        _row(id: 'a', type: 'car', at: now.subtract(const Duration(minutes: 5))),
        _row(
          id: 'b',
          type: 'stairs',
          at: now.subtract(const Duration(hours: 2)),
        ),
      ],
    ));
    await tester.pumpWidget(host(history));
    await tester.pump();

    expect(find.text('Car'), findsWidgets);
    expect(find.text('Stairs'), findsWidgets);
    expect(find.text('14.84000, 120.81000'), findsNWidgets(2));
    expect(find.text('About 2 metres'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilterChip, 'Stairs'));
    await tester.pump();
    expect(find.text('About 2 metres'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Car'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
