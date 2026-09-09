import 'package:camera/camera.dart';

/// Stand-in for platforms with no ML Kit. Refuses honestly: [start] returns
/// false, and the screen already has a path for a camera that would not
/// open.
class TextReader {
  CameraController? get controller => null;

  Future<bool> start() async => false;

  Future<String?> capture() async => null;

  Future<void> dispose() async {}
}
