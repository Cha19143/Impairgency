/// Picks the right [StairsDetector] for the platform: TFLite where there is
/// `dart:ffi`, a refusal on the web. See `scan_service.dart`.
library;

export 'stairs_detector_stub.dart'
    if (dart.library.io) 'stairs_detector_io.dart';
