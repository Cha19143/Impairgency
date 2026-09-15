import '../core/vision/faces.dart';
import '../core/vision/yuv_frame.dart';

/// A person the object detector boxed, as fractions of the upright frame.
class PersonBox {
  const PersonBox(this.left, this.top, this.right, this.bottom);
  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// Stand-in for platforms with no TFLite. Never loads.
class FaceRecognizer {
  FaceRecognizer._();

  static Future<FaceRecognizer?> load() async => null;

  Future<List<FaceObservation>> analyse(
    YuvFrame frame, {
    List<PersonBox> people = const [],
    bool centre = false,
    required DateTime at,
  }) async =>
      const [];

  Future<void> close() async {}
}
