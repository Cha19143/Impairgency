/// JPEG for one gray frame. Called when a clip closes, not from the camera.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'event_clip.dart';

/// Encodes [frame] as a grayscale JPEG.
///
/// The camera callback only copies Y. This is the slow part, and it runs
/// after the clip has closed.
Uint8List encodeGrayJpeg(GrayFrame frame, {int quality = kClipJpegQuality}) {
  final image = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: Uint8List.fromList(frame.pixels).buffer,
    numChannels: 1,
  );
  return img.encodeJpg(image, quality: quality);
}

/// One JPEG per frame, in order. The argument and the result are what
/// `compute` can send to another isolate.
List<Uint8List> encodeClipJpegs(List<GrayFrame> frames) =>
    [for (final frame in frames) encodeGrayJpeg(frame)];
