import '../core/vision/detection.dart';
import '../core/vision/yuv_frame.dart';

/// Stand-in for platforms with no TFLite. Never loads.
class StairsDetector {
  StairsDetector._();

  static Future<StairsDetector?> load() async => null;

  Future<List<Detection>> detect(YuvFrame frame) async => const [];

  Future<void> close() async {}
}
