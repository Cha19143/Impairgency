/// Colour out of a camera frame, the right way up.
///
/// Cameras hand frames over as YUV - brightness at full size, colour at a
/// quarter - in the sensor's orientation, which on a phone held upright is
/// lying on its side. The scan service's own loop does this for YOLO in one
/// tight pass. Faces need it differently: a small square cut from wherever a
/// head is, and then a face turned upright pixel by pixel. So this is the same
/// arithmetic as that loop, one pixel at a time, with no camera in it - the
/// planes are plain bytes, and a test builds them.
library;

import 'dart:typed_data';

import 'blazeface.dart';
import 'face_align.dart';

class YuvFrame {
  YuvFrame({
    required this.width,
    required this.height,
    required this.y,
    required this.u,
    required this.v,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.biPlanar,
    required int sensorOrientation,
  }) : quarterTurns = ((sensorOrientation ~/ 90) % 4 + 4) % 4;

  /// The sensor's size, before turning.
  final int width;
  final int height;

  final Uint8List y;
  final Uint8List u;

  /// The same bytes as [u] when [biPlanar]: iOS interleaves the two.
  final Uint8List v;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final bool biPlanar;
  final int quarterTurns;

  int get uprightWidth => quarterTurns.isOdd ? height : width;
  int get uprightHeight => quarterTurns.isOdd ? width : height;

  /// Red, green and blue, 0 to 255, of the upright pixel nearest [x], [y] -
  /// or null outside the frame.
  ({double r, double g, double b})? rgbAt(double x, double y) {
    final out = Float32List(3);
    if (!writeRgb(x, y, out, 0, scale: 1, shift: 0)) return null;
    return (r: out[0].toDouble(), g: out[1].toDouble(), b: out[2].toDouble());
  }

  /// [rgbAt], written straight into [out] at [at] as `value * scale + shift`,
  /// with nothing allocated: a face crop reads twenty-five thousand pixels,
  /// a few times a second. False, and nothing written, outside the frame.
  ///
  /// [stride] is how far apart the three values go: 1 for red, green, blue
  /// side by side, a whole plane for a model that takes all of red, then all
  /// of green, then all of blue.
  bool writeRgb(double x, double y, Float32List out, int at,
      {required double scale, required double shift, int stride = 1}) {
    final source = _source(x, y);
    if (source < 0) return false;
    final sx = source % width;
    final sy = source ~/ width;
    final yIndex = sy * yRowStride + sx;
    final luma = yIndex < this.y.length ? this.y[yIndex].toDouble() : 0.0;
    final uvIndex = (sy ~/ 2) * uvRowStride + (sx ~/ 2) * uvPixelStride;
    final cb = (uvIndex < u.length ? u[uvIndex] : 128) - 128.0;
    final cr = (biPlanar
            ? (uvIndex + 1 < v.length ? v[uvIndex + 1] : 128)
            : (uvIndex < v.length ? v[uvIndex] : 128)) -
        128.0;
    out[at] = (luma + 1.402 * cr).clamp(0.0, 255.0) * scale + shift;
    out[at + stride] =
        (luma - 0.344136 * cb - 0.714136 * cr).clamp(0.0, 255.0) * scale +
            shift;
    out[at + 2 * stride] =
        (luma + 1.772 * cb).clamp(0.0, 255.0) * scale + shift;
    return true;
  }

  /// Brightness, 0 to 255, of the upright pixel nearest [x], [y] - or 0
  /// outside the frame. Straight from the Y plane: the stairs search looks at
  /// edges in brightness, and colour would cost three times the arithmetic
  /// for nothing it uses.
  int lumaAt(double x, double y) {
    final source = _source(x, y);
    if (source < 0) return 0;
    final index = (source ~/ width) * yRowStride + source % width;
    return index < this.y.length ? this.y[index] : 0;
  }

  /// The sensor pixel under upright [x], [y], as `row * width + column`, or
  /// -1 outside the frame. Packed into one number so the pixel loops that
  /// call it allocate nothing.
  int _source(double x, double y) {
    final dx = x.floor();
    final dy = y.floor();
    if (dx < 0 || dy < 0 || dx >= uprightWidth || dy >= uprightHeight) {
      return -1;
    }
    // Not a record: one per pixel is the allocation the packing avoids.
    switch (quarterTurns) {
      case 1:
        return (height - 1 - dx) * width + dy;
      case 2:
        return (height - 1 - dy) * width + (width - 1 - dx);
      case 3:
        return dx * width + (width - 1 - dy);
      default:
        return dy * width + dx;
    }
  }
}

/// A square of the upright frame, in its pixels. May reach past the edges.
class FrameSquare {
  const FrameSquare(this.left, this.top, this.size);
  final double left;
  final double top;
  final double size;

  /// A fraction of this square, as frame pixels.
  FacePoint toFrame(double fx, double fy) =>
      FacePoint(left + fx * size, top + fy * size);
}

/// The square around the head of a person the detector boxed, from the
/// fractions of the frame YOLO gives: the top 45 percent of the box, as wide
/// as the box, squared up around its centre.
FrameSquare headSquare(YuvFrame frame,
    {required double left,
    required double top,
    required double right,
    required double bottom}) {
  final w = (right - left) * frame.uprightWidth;
  final h = (bottom - top) * 0.45 * frame.uprightHeight;
  final size = (w > h ? w : h).clamp(48.0, double.infinity).toDouble();
  final cx = (left + right) / 2 * frame.uprightWidth;
  final cy = (top * frame.uprightHeight) + h / 2;
  return FrameSquare(cx - size / 2, cy - size / 2, size);
}

/// The middle of the frame, for taking a face down when the person holding
/// the phone is pointing it straight at them.
FrameSquare centreSquare(YuvFrame frame) {
  final shorter = frame.uprightWidth < frame.uprightHeight
      ? frame.uprightWidth
      : frame.uprightHeight;
  final size = shorter * 0.8;
  return FrameSquare((frame.uprightWidth - size) / 2,
      (frame.uprightHeight - size) / 2, size);
}

/// Fills [out] - `side` by `side` by 3, rows of red, green, blue - with
/// [square] of [frame], each value scaled as `value * scale + shift`. Outside
/// the frame is [pad].
void fillSquare(
  YuvFrame frame,
  FrameSquare square,
  Float32List out, {
  required int side,
  required double scale,
  required double shift,
  double pad = 0,
}) {
  final step = square.size / side;
  for (var row = 0; row < side; row++) {
    final fy = square.top + (row + 0.5) * step;
    for (var col = 0; col < side; col++) {
      final at = (row * side + col) * 3;
      if (!frame.writeRgb(square.left + (col + 0.5) * step, fy, out, at,
          scale: scale, shift: shift)) {
        out[at] = pad;
        out[at + 1] = pad;
        out[at + 2] = pad;
      }
    }
  }
}

/// Fills [out] with the face [toCrop] lines up: for each pixel of the crop,
/// the frame pixel the inverse of [toCrop] lands on.
void fillAligned(
  YuvFrame frame,
  Similarity toCrop,
  Float32List out, {
  int side = kFaceCropSide,
  required double scale,
  required double shift,
  double pad = 0,
}) {
  final back = toCrop.inverse();
  for (var row = 0; row < side; row++) {
    final v = row + 0.5;
    for (var col = 0; col < side; col++) {
      final at = (row * side + col) * 3;
      final u = col + 0.5;
      // The inverse, written out rather than through a point per pixel.
      final x = back.a * u - back.b * v + back.tx;
      final y = back.b * u + back.a * v + back.ty;
      if (!frame.writeRgb(x, y, out, at, scale: scale, shift: shift)) {
        out[at] = pad;
        out[at + 1] = pad;
        out[at + 2] = pad;
      }
    }
  }
}
