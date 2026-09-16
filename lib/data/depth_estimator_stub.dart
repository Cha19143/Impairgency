import '../core/vision/depth.dart';
import '../core/vision/yuv_frame.dart';

/// Stand-in for platforms with no TFLite. Never loads.
class DepthEstimator {
  DepthEstimator._();

  static Future<DepthEstimator?> load() async => null;

  Future<DepthReading> estimate(YuvFrame frame) async => DepthReading.none;

  Future<void> close() async {}
}
