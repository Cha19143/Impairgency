import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../core/vision/detection.dart';
import '../core/vision/faces.dart';

/// Stand-in for platforms with no TFLite.
///
/// `tflite_flutter` is built on `dart:ffi`, which does not exist on the web.
/// The scan route is never registered on web — the router splits on `kIsWeb` —
/// but an unconditional import still has to compile, so this is what web gets.
///
/// It refuses honestly rather than pretending: [loadModel] returns false, and
/// the screen already has a path for a model that would not load.
class ScanService {
  CameraController? get controller => null;
  bool get isReady => false;

  Future<bool> loadModel() async {
    debugPrint('Scan is not available on this platform.');
    return false;
  }

  Future<bool> start(void Function(ScanFrame) onFrame) async => false;

  /// Recognises nobody here.
  Future<bool> watchFaces(FaceWatch? watch) async => false;

  Future<void> dispose() async {}
}
