/// Picks the right [DepthEstimator] for the platform: TFLite where there is
/// `dart:ffi`, a refusal on the web. See `scan_service.dart`.
library;

export 'depth_estimator_stub.dart'
    if (dart.library.io) 'depth_estimator_io.dart';
