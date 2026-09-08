import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/yolo.dart';

/// One anchor's worth of what the model would have said.
typedef Slot = ({
  double cx,
  double cy,
  double w,
  double h,
  int cls,
  double score,
});

/// Builds a `[1, 4 + classes, anchors]` tensor the way TFLite lays one out.
///
/// Row-major: every centre-x, then every centre-y, and so on. Written out here
/// rather than reusing the reader's own arithmetic, so a test cannot agree with
/// the code by making the same mistake twice.
Float32List tensor(List<Slot?> slots, {int classes = kYoloClasses}) {
  final anchors = slots.length;
  final out = Float32List((kBoxRows + classes) * anchors);
  for (var a = 0; a < anchors; a++) {
    final slot = slots[a];
    if (slot == null) continue;
    out[0 * anchors + a] = slot.cx;
    out[1 * anchors + a] = slot.cy;
    out[2 * anchors + a] = slot.w;
    out[3 * anchors + a] = slot.h;
    out[(kBoxRows + slot.cls) * anchors + a] = slot.score;
  }
  return out;
}

Slot slot({
  double cx = 0.5,
  double cy = 0.5,
  double w = 0.2,
  double h = 0.2,
  int cls = 0,
  double score = 0.9,
}) =>
    (cx: cx, cy: cy, w: w, h: h, cls: cls, score: score);

List<RawBox> decode(Float32List out, int anchors, {double minScore = 0.5}) =>
    decodeYolo(out, anchors: anchors, minScore: minScore);

void main() {
  group('reading the tensor', () {
    test('a box is read down its own column, not along a row', () {
      // The mistake this exists for. `[1, 84, 2100]` reads naturally as 84
      // things of 2100, and the boxes are the other way up: 2100 things of 84.
      // Reading it the wrong way still produces four finite numbers per
      // anchor, so it does not throw and it does not look wrong — it just
      // describes a room that is not there.
      final out = tensor([
        null,
        slot(cx: 0.25, cy: 0.75, w: 0.1, h: 0.2, cls: 3, score: 0.8),
        null,
      ]);

      final boxes = decode(out, 3);
      expect(boxes, hasLength(1));
      expect(boxes.single.centerX, closeTo(0.25, 1e-6));
      expect(boxes.single.centerY, closeTo(0.75, 1e-6));
      expect(boxes.single.width, closeTo(0.1, 1e-6));
      expect(boxes.single.height, closeTo(0.2, 1e-6));
      expect(boxes.single.classIndex, 3);
      expect(boxes.single.score, closeTo(0.8, 1e-6));
    });

    test('corners come from a centre and a size', () {
      final out = tensor([slot(cx: 0.5, cy: 0.4, w: 0.2, h: 0.6)]);
      final box = decode(out, 1).single;

      expect(box.left, closeTo(0.4, 1e-6));
      expect(box.right, closeTo(0.6, 1e-6));
      expect(box.top, closeTo(0.1, 1e-6));
      expect(box.bottom, closeTo(0.7, 1e-6));
    });

    test('the strongest class on an anchor is the one reported', () {
      final anchors = 1;
      final out = tensor([slot(cls: 2, score: 0.6)]);
      // A second, stronger class on the same anchor.
      out[(kBoxRows + 17) * anchors + 0] = 0.85;

      final box = decode(out, anchors).single;
      expect(box.classIndex, 17);
      expect(box.score, closeTo(0.85, 1e-6));
    });

    test('anything under the threshold is noise, not an object', () {
      final out = tensor([slot(score: 0.49), slot(cx: 0.1, score: 0.51)]);
      final boxes = decode(out, 2, minScore: 0.5);

      expect(boxes, hasLength(1));
      expect(boxes.single.centerX, closeTo(0.1, 1e-6));
    });

    test('a score exactly at the threshold is kept, not dropped', () {
      // kMinScore is documented as the confidence *below* which a detection is
      // noise, and guidanceFor filters with >=. A decoder using > here would
      // quietly disagree with the layer it feeds.
      final out = tensor([slot(score: 0.5)]);
      expect(decode(out, 1, minScore: 0.5), hasLength(1));
    });

    test('an empty frame decodes to nothing rather than to something', () {
      expect(decode(tensor([null, null, null]), 3), isEmpty);
    });

    test('a tensor of the wrong size is refused, not read anyway', () {
      // Re-exporting the model at another size, or pointing this at the SSD
      // graph, must not quietly read past the end of one row into the next.
      final out = tensor([slot()], classes: kYoloClasses);
      expect(
        () => decodeYolo(out, anchors: 2, minScore: 0.5),
        throwsArgumentError,
      );
    });
  });

  group('one object, one announcement', () {
    test('the same object under two labels is suppressed to one', () {
      // What class-aware suppression would leave behind: guidance names the
      // strongest object and then a second one with a different label, so a
      // chair the model half-reads as a bench becomes "Stop. chair right in
      // front of you. bench ahead" — for one thing to walk into.
      final out = tensor([
        slot(cx: 0.5, cy: 0.5, w: 0.4, h: 0.4, cls: 56, score: 0.9),
        slot(cx: 0.51, cy: 0.5, w: 0.4, h: 0.4, cls: 13, score: 0.7),
      ]);

      final boxes = decode(out, 2);
      expect(boxes, hasLength(1));
      expect(boxes.single.classIndex, 56, reason: 'the more confident one');
    });

    test('a person in front of a bus is not swallowed by it', () {
      // The cost of suppressing across classes, and the reason it is
      // affordable: a small box inside a large one shares only its own area,
      // so the overlap never approaches the threshold.
      final out = tensor([
        slot(cx: 0.5, cy: 0.5, w: 0.9, h: 0.5, cls: 5, score: 0.86),
        slot(cx: 0.4, cy: 0.6, w: 0.15, h: 0.45, cls: 0, score: 0.84),
      ]);

      final boxes = decode(out, 2);
      expect(boxes, hasLength(2));
      expect(boxes.map((b) => b.classIndex), containsAll([5, 0]));
    });

    test('two separate objects are two objects', () {
      final out = tensor([
        slot(cx: 0.2, cy: 0.5, w: 0.2, h: 0.2, score: 0.9),
        slot(cx: 0.8, cy: 0.5, w: 0.2, h: 0.2, score: 0.8),
      ]);
      expect(decode(out, 2), hasLength(2));
    });

    test('the strongest box wins, whichever order they arrive in', () {
      final out = tensor([
        slot(cx: 0.5, w: 0.4, h: 0.4, cls: 1, score: 0.6),
        slot(cx: 0.5, w: 0.4, h: 0.4, cls: 2, score: 0.95),
      ]);
      expect(decode(out, 2).single.classIndex, 2);
    });

    test('the number of boxes is bounded', () {
      final slots = [
        for (var i = 0; i < 40; i++)
          slot(cx: 0.01 + i * 0.02, cy: 0.5, w: 0.005, h: 0.005, score: 0.9),
      ];
      final boxes = decodeYolo(tensor(slots),
          anchors: slots.length, minScore: 0.5, maxBoxes: 5);
      expect(boxes, hasLength(5));
    });
  });

  group('overlap', () {
    RawBox box(double l, double t, double r, double b) => RawBox(
          classIndex: 0,
          score: 1,
          centerX: (l + r) / 2,
          centerY: (t + b) / 2,
          width: r - l,
          height: b - t,
        );

    test('identical boxes overlap completely', () {
      expect(intersectionOverUnion(box(0, 0, 1, 1), box(0, 0, 1, 1)),
          closeTo(1.0, 1e-9));
    });

    test('boxes that do not touch overlap not at all', () {
      expect(intersectionOverUnion(box(0, 0, 0.2, 0.2), box(0.5, 0.5, 0.9, 0.9)),
          0);
    });

    test('boxes that share an edge still overlap not at all', () {
      expect(
          intersectionOverUnion(box(0, 0, 0.5, 1), box(0.5, 0, 1, 1)), 0);
    });

    test('a quarter shared out of seven quarters', () {
      // Two unit squares offset by half in both directions: they share 0.25,
      // and cover 1.75 between them.
      expect(
        intersectionOverUnion(box(0, 0, 1, 1), box(0.5, 0.5, 1.5, 1.5)),
        closeTo(0.25 / 1.75, 1e-9),
      );
    });
  });

  group('fitting a frame into a square', () {
    test('a portrait frame is padded left and right, not top and bottom', () {
      final box = Letterbox(frameWidth: 240, frameHeight: 320, side: 320);
      expect(box.drawWidth, 240);
      expect(box.drawHeight, 320);
      expect(box.padX, 40);
      expect(box.padY, 0);
    });

    test('a square frame needs no padding at all', () {
      final box = Letterbox(frameWidth: 480, frameHeight: 480, side: 320);
      expect(box.padX, 0);
      expect(box.padY, 0);
      expect(box.toFrameX(0.25), closeTo(0.25, 1e-9));
      expect(box.toFrameY(0.75), closeTo(0.75, 1e-9));
    });

    test('the middle of the input is the middle of the frame', () {
      final box = Letterbox(frameWidth: 240, frameHeight: 320, side: 320);
      expect(box.toFrameX(0.5), closeTo(0.5, 1e-9));
      expect(box.toFrameY(0.5), closeTo(0.5, 1e-9));
    });

    test('the edges of the frame come back as the edges of the frame', () {
      // Not undoing the padding drags every direction towards the middle, so
      // something at the very edge of view is announced as "ahead". The
      // padding is a quarter of this input's width, which is the difference
      // between "on your left" and "ahead" for anything past x = 0.35.
      final box = Letterbox(frameWidth: 240, frameHeight: 320, side: 320);
      expect(box.toFrameX(40 / 320), closeTo(0.0, 1e-9));
      expect(box.toFrameX(280 / 320), closeTo(1.0, 1e-9));
      expect(box.toFrameY(0.0), closeTo(0.0, 1e-9));
      expect(box.toFrameY(1.0), closeTo(1.0, 1e-9));
    });

    test('a square object stays square, which is what extent depends on', () {
      // The regression the letterbox exists for. Stretching a 4:3 frame across
      // a square inflates every width by a third, and extent — the app's only
      // depth cue — is the larger side of the box. A stretched frame reports a
      // metre-wide obstacle across the room as one at arm's length.
      final box = Letterbox(frameWidth: 320, frameHeight: 240, side: 320);

      final width = box.toFrameX(0.6) - box.toFrameX(0.4);
      final height = box.toFrameY(0.6) - box.toFrameY(0.4);
      final aspect = (width * 320) / (height * 240);
      expect(aspect, closeTo(1.0, 1e-6),
          reason: 'a square in the world is a square in the frame');
    });

    test('padding is the grey the model was trained to ignore', () {
      expect(Letterbox.padValue, closeTo(114 / 255, 1e-9));
    });
  });
}
