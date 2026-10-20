import 'package:sensors_plus/sensors_plus.dart';

import '../core/motion/fall_detector.dart';

/// Accelerometer readings. A test hands in its own stream.
abstract interface class MotionSource {
  Stream<MotionSample> get samples;
}

/// The phone's accelerometer, including gravity, so a free fall is visible.
class SensorsMotionSource implements MotionSource {
  const SensorsMotionSource();

  @override
  Stream<MotionSample> get samples => accelerometerEventStream(
    samplingPeriod: const Duration(milliseconds: 50),
  ).map(
    (event) => MotionSample(
      at: DateTime.now(),
      x: event.x,
      y: event.y,
      z: event.z,
    ),
  );
}
