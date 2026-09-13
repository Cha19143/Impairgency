import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/guardian/activity.dart';
import 'package:impairgency/core/guardian/watched_user.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/guardian/screens/guardian_home_screen.dart';

class RecordingSpeaker implements Speaker {
  final List<String> said = [];
  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;
  @override
  Future<void> repeat() async {}
  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);
  @override
  Future<void> stop() async {}
}

final now = DateTime.utc(2026, 9, 9, 12);

Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

GuardianHomeScreen screen({
  List<WatchedUser> users = const [],
  Future<bool> Function(CallTarget)? onCall,
  RecordingSpeaker? speaker,
  bool loading = false,
}) =>
    GuardianHomeScreen(
      users: users,
      loading: loading,
      now: () => now,
      speaker: speaker ?? RecordingSpeaker(),
      onCall: onCall ?? (_) async => true,
      onOpenMap: (_) {},
      onEnterCode: () {},
      onSignOut: () {},
    );

void main() {
  testWidgets('with nobody paired, the way in is the code', (tester) async {
    await tester.pumpWidget(host(screen()));
    await tester.pump();
    expect(find.text('Enter their code'), findsOneWidget);
    expect(find.textContaining('not watching over anyone yet'), findsOneWidget);
  });

  testWidgets('shows each person, where they are, and a Call button',
      (tester) async {
    CallTarget? dialled;
    await tester.pumpWidget(host(screen(
      users: [
        WatchedUser(
          uid: 'u1',
          name: 'Ana',
          phone: '0917',
          sharesLocation: true,
          fix: LocationFix(
              latitude: 14.79,
              longitude: 120.92,
              accuracyMetres: 10,
              at: now.subtract(const Duration(minutes: 3))),
        ),
      ],
      onCall: (t) async {
        dialled = t;
        return true;
      },
    )));
    await tester.pump();

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Ana was last seen 3 minutes ago.'), findsOneWidget);
    expect(find.text('Open on a map'), findsOneWidget);

    await tester.tap(find.text('Call'));
    await tester.pump();
    expect(dialled!.number, '0917');
    expect(dialled!.label, 'Call Ana');
  });

  testWidgets('nobody to call is said, not silently ignored', (tester) async {
    final speaker = RecordingSpeaker();
    var calls = 0;
    await tester.pumpWidget(host(screen(
      users: const [WatchedUser(uid: 'u1', name: 'Ana')],
      speaker: speaker,
      onCall: (_) async {
        calls++;
        return true;
      },
    )));
    await tester.pump();
    await tester.tap(find.text('Call'));
    await tester.pump();

    expect(calls, 0);
    expect(speaker.said.last, contains('nobody to call'));
    expect(find.textContaining('nobody to call'), findsWidgets);
  });

  testWidgets('a dialler that refuses is reported', (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(screen(
      users: const [WatchedUser(uid: 'u1', name: 'Ana', phone: '0917')],
      speaker: speaker,
      onCall: (_) async => false,
    )));
    await tester.pump();
    await tester.tap(find.text('Call'));
    await tester.pump();
    expect(speaker.said.last, contains('could not be started'));
  });

  testWidgets('no map button without a position, and says why', (tester) async {
    await tester.pumpWidget(host(screen(
      users: const [WatchedUser(uid: 'u1', name: 'Ana', phone: '0917')],
    )));
    await tester.pump();
    expect(find.text('Open on a map'), findsNothing);
    expect(find.textContaining('not sharing their location'), findsOneWidget);
  });

  testWidgets('speaks a summary on arrival, once the data is there',
      (tester) async {
    final speaker = RecordingSpeaker();
    await tester.pumpWidget(host(screen(loading: true, speaker: speaker)));
    await tester.pump();
    expect(speaker.said, isEmpty, reason: 'nothing to say about a spinner');

    await tester.pumpWidget(host(screen(
      users: const [WatchedUser(uid: 'u1', name: 'Ana')],
      speaker: speaker,
    )));
    await tester.pump();
    expect(speaker.said.first, 'Guardian');
    expect(speaker.said.join(' '), contains('Ana is not sharing'));
  });

  testWidgets('a recent SOS is the first thing on the card', (tester) async {
    await tester.pumpWidget(host(screen(
      users: [
        WatchedUser(
            uid: 'u1',
            name: 'Ana',
            lastSos: now.subtract(const Duration(minutes: 2))),
      ],
    )));
    await tester.pump();
    expect(find.text('Called for help 2 minutes ago.'), findsOneWidget);
  });

  testWidgets('recent activity: the last few things, newest first',
      (tester) async {
    final user = WatchedUser(
      uid: 'u1',
      name: 'Ana',
      sharesActivity: true,
      activity: [
        ActivityEvent(
            kind: ActivityKind.obstacle,
            detail: 'chair',
            at: now.subtract(const Duration(minutes: 2))),
        ActivityEvent(
            kind: ActivityKind.textRead,
            detail: 'MEDICINE',
            at: now.subtract(const Duration(minutes: 15))),
        ActivityEvent(
            kind: ActivityKind.journey,
            detail: 'Work',
            at: now.subtract(const Duration(hours: 1))),
        ActivityEvent(
            kind: ActivityKind.obstacle,
            detail: 'car',
            at: now.subtract(const Duration(hours: 2))),
      ],
    );
    await tester.pumpWidget(host(screen(users: [user])));
    await tester.pump();
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Obstacle: chair'), findsOneWidget);
    expect(find.text('Read: MEDICINE'), findsOneWidget);
    expect(find.text('Set off for Work'), findsOneWidget);
    // Three on the card, not four.
    expect(find.text('Obstacle: car'), findsNothing);
  });

  testWidgets('says when activity is not shared, and when nothing happened',
      (tester) async {
    await tester.pumpWidget(host(screen(
        users: const [WatchedUser(uid: 'u1', name: 'Ana')])));
    await tester.pump();
    expect(find.textContaining('not sharing what the app notices'),
        findsOneWidget);

    await tester.pumpWidget(host(screen(users: const [
      WatchedUser(uid: 'u1', name: 'Ana', sharesActivity: true)
    ])));
    await tester.pump();
    expect(find.text('Nothing noticed yet.'), findsOneWidget);
  });

  testWidgets('Live location needs a position and a handler',
      (tester) async {
    final withFix = WatchedUser(
      uid: 'u1',
      name: 'Ana',
      sharesLocation: true,
      fix: LocationFix(
          latitude: 14.79, longitude: 120.92, accuracyMetres: 10, at: now),
    );
    WatchedUser? opened;
    await tester.pumpWidget(host(GuardianHomeScreen(
      users: [withFix],
      now: () => now,
      speaker: RecordingSpeaker(),
      onCall: (_) async => true,
      onOpenMap: (_) {},
      onLiveLocation: (u) => opened = u,
      onEnterCode: () {},
      onSignOut: () {},
    )));
    await tester.pump();
    await tester.tap(find.text('Live location'));
    expect(opened?.uid, 'u1');

    await tester.pumpWidget(host(screen(users: [withFix])));
    await tester.pump();
    expect(find.text('Live location'), findsNothing);
  });
}
