import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:impairgency/core/clips/event_clip.dart';
import 'package:impairgency/core/clips/gray_jpeg.dart';

void main() {
  test('a gray frame becomes a small jpeg off the calling stack', () async {
    final frame = GrayFrame(
      at: DateTime.utc(2026, 10, 20),
      width: kClipWidth,
      height: kClipHeight,
      pixels: Uint8List(kClipWidth * kClipHeight)..fillRange(0, kClipWidth * kClipHeight, 180),
    );
    final jpegs = await compute(encodeClipJpegs, [frame]);
    expect(jpegs, hasLength(1));
    expect(jpegs.single.length, lessThan(20 * 1024));
    expect(jpegs.single[0], 0xff);
    expect(jpegs.single[1], 0xd8);
    final decoded = img.decodeJpg(jpegs.single);
    expect(decoded, isNotNull);
    expect(decoded!.width, kClipWidth);
    expect(decoded.height, kClipHeight);
  });
}
