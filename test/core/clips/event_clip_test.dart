import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/clips/event_clip.dart';
import 'package:impairgency/core/vision/yuv_frame.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 20, 12);

  GrayFrame frameAt(DateTime at, {int value = 1}) => GrayFrame(
        at: at,
        width: 2,
        height: 2,
        pixels: Uint8List.fromList([value, value, value, value]),
      );

  ClipAssembler open() => ClipAssembler();

  test('kClipsEnabled is on', () {
    expect(kClipsEnabled, isTrue);
  });

  test('the buffer keeps eight seconds and the clip starts with them', () {
    final clips = open();
    clips.addFrame(frameAt(t0.subtract(const Duration(seconds: 9)), value: 1));
    clips.addFrame(frameAt(t0.subtract(const Duration(seconds: 8)), value: 2));
    clips.addFrame(frameAt(t0, value: 3));
    expect(clips.note(kClipTriggerObstacle, t0), isTrue);
    final closed = clips.takeDue(t0.add(kClipTail));
    expect(closed, isNotNull);
    expect(closed!.frames.map((f) => f.pixels.first), [2, 3]);
    expect(closed.triggers, [kClipTriggerObstacle]);
    expect(closed.at, t0);
  });

  test('a second trigger during the tail merges and restarts it', () {
    final clips = open();
    expect(clips.note(kClipTriggerObstacle, t0), isTrue);
    expect(clips.note(kClipTriggerFall, t0.add(const Duration(seconds: 2))), isTrue);
    expect(clips.takeDue(t0.add(const Duration(seconds: 4))), isNull);
    final closed = clips.takeDue(t0.add(const Duration(seconds: 5)));
    expect(closed!.triggers, [kClipTriggerObstacle, kClipTriggerFall]);
    expect(closed.endedAt, t0.add(const Duration(seconds: 5)));
  });

  test('the tail cannot be pushed past the cap', () {
    final clips = open();
    clips.note(kClipTriggerObstacle, t0);
    clips.note(kClipTriggerFall, t0.add(const Duration(seconds: 2)));
    clips.note(kClipTriggerDeviation, t0.add(const Duration(seconds: 4)));
    clips.note(kClipTriggerStationary, t0.add(const Duration(seconds: 6)));
    clips.note(kClipTriggerSos, t0.add(const Duration(seconds: 8)));
    expect(clips.deadline, t0.add(kClipMaxAfter));
    expect(clips.takeDue(t0.add(const Duration(seconds: 9))), isNull);
    final closed = clips.takeDue(t0.add(kClipMaxAfter));
    expect(closed, isNotNull);
    expect(closed!.triggers, [
      kClipTriggerObstacle,
      kClipTriggerFall,
      kClipTriggerDeviation,
      kClipTriggerStationary,
      kClipTriggerSos,
    ]);
  });

  test('a new clip waits out the gap, and a merge does not reset it', () {
    final clips = open();
    clips.note(kClipTriggerObstacle, t0);
    clips.note(kClipTriggerFall, t0.add(const Duration(seconds: 1)));
    clips.takeDue(t0.add(const Duration(seconds: 5)));
    expect(
      clips.note(kClipTriggerObstacle, t0.add(const Duration(seconds: 59))),
      isFalse,
    );
    expect(clips.note(kClipTriggerObstacle, t0.add(kClipMinGap)), isTrue);
  });

  test('the hourly cap stops a new clip, and SOS does not count or wait', () {
    final clips = open();
    for (var i = 0; i < kClipHourlyCap; i++) {
      final at = t0.add(Duration(seconds: 61 * i));
      expect(clips.note(kClipTriggerObstacle, at), isTrue, reason: 'clip $i');
      clips.takeDue(at.add(kClipTail));
    }
    final blocked = t0.add(Duration(seconds: 61 * kClipHourlyCap));
    expect(clips.note(kClipTriggerFall, blocked), isFalse);
    expect(clips.note(kClipTriggerSos, blocked), isTrue);
    clips.takeDue(blocked.add(kClipTail));
    expect(clips.note(kClipTriggerObstacle, blocked.add(kClipTail)), isFalse);

    final later = t0.add(const Duration(minutes: 61));
    expect(clips.note(kClipTriggerObstacle, later), isTrue);
  });

  test('SOS still starts when the last clip was a moment ago', () {
    final clips = open();
    clips.note(kClipTriggerObstacle, t0);
    clips.takeDue(t0.add(kClipTail));
    expect(clips.note(kClipTriggerSos, t0.add(const Duration(seconds: 5))), isTrue);
    clips.takeDue(t0.add(const Duration(seconds: 9)));
    expect(clips.note(kClipTriggerObstacle, t0.add(kClipMinGap)), isTrue);
  });

  test('turning the assembler off keeps nothing', () {
    final clips = ClipAssembler(enabled: false);
    clips.addFrame(frameAt(t0));
    expect(clips.note(kClipTriggerSos, t0), isFalse);
    expect(clips.takeDue(t0.add(const Duration(hours: 1))), isNull);
  });

  test('gray is sampled from the upright Y plane', () {
    // 4 by 2, row-major. A 2 by 1 thumbnail samples the centres of the
    // bottom row: 60 and 80.
    final y = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
    final frame = YuvFrame(
      width: 4,
      height: 2,
      y: y,
      u: Uint8List(2),
      v: Uint8List(2),
      yRowStride: 4,
      uvRowStride: 2,
      uvPixelStride: 1,
      biPlanar: false,
      sensorOrientation: 0,
    );
    final pixels = subsampleGray(frame, width: 2, height: 1);
    expect(pixels, [60, 80]);
  });
}
