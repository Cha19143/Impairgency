import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/admin/screens/event_clips_screen.dart';
import 'package:impairgency/core/clips/event_clip.dart';
import 'package:impairgency/core/clips/gray_jpeg.dart';

void main() {
  final at = DateTime.utc(2026, 10, 20, 9);

  EventClipRecord clip({
    required String id,
    required List<String> triggers,
    bool frames = false,
    String userId = 'u1',
  }) =>
      EventClipRecord(
        id: id,
        userId: userId,
        triggers: triggers,
        at: at,
        endedAt: at.add(const Duration(seconds: 3)),
        frameCount: frames ? 2 : 0,
        hasFrames: frames,
      );

  Uint8List jpeg(int shade) => encodeGrayJpeg(GrayFrame(
        at: at,
        width: 4,
        height: 4,
        pixels: Uint8List(16)..fillRange(0, 16, shade),
      ));

  Future<void> pump(
    WidgetTester tester,
    List<EventClipRecord> clips, {
    Future<List<StoredClipFrame>> Function(String id)? load,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EventClipsScreen(
          clips: clips,
          users: const [],
          loadFrames: load ?? (_) async => const [],
        ),
      ),
    ));
  }

  testWidgets('a clip with no frames says the camera was off', (tester) async {
    await pump(tester, [
      clip(id: 'sos', triggers: const [kClipTriggerSos]),
    ]);
    await tester.tap(find.byKey(const ValueKey('clip-sos')));
    await tester.pump();
    expect(find.text(kClipNoFramesMessage), findsOneWidget);
  });

  testWidgets('the trigger filter hides the other clips', (tester) async {
    await pump(tester, [
      clip(id: 'car', triggers: const [kClipTriggerObstacle]),
      clip(id: 'sos', triggers: const [kClipTriggerSos]),
    ]);
    expect(find.byKey(const ValueKey('clip-car')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('Trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'SOS').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clip-car')), findsNothing);
    expect(find.byKey(const ValueKey('clip-sos')), findsOneWidget);
  });

  testWidgets('the player steps through the frames', (tester) async {
    final pictures = [
      StoredClipFrame(index: 0, jpeg: jpeg(20), width: 4, height: 4),
      StoredClipFrame(index: 1, jpeg: jpeg(220), width: 4, height: 4),
    ];
    await pump(
      tester,
      [clip(id: 'car', triggers: const [kClipTriggerObstacle], frames: true)],
      load: (_) async => pictures,
    );
    await tester.tap(find.byKey(const ValueKey('clip-car')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Picture 1 of 2'), findsOneWidget);
    await tester.pump(kClipFrameGap);
    expect(find.text('Picture 2 of 2'), findsOneWidget);
    await tester.pump(kClipFrameGap);
    expect(find.text('Play'), findsOneWidget);
  });
}
