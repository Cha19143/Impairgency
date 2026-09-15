/// Picks the right [FaceRecognizer] for the platform: TFLite where there is
/// `dart:ffi`, a refusal on the web. See `scan_service.dart`.
library;

export 'face_recognizer_stub.dart'
    if (dart.library.io) 'face_recognizer_io.dart';
