import 'dart:io';

import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

/// The camera in text-reading mode: a still, not a stream.
///
/// The scan screen streams frames because an obstacle is coming towards the
/// user; a page is not. One sharp photograph, focused and at full
/// resolution, reads better than thirty blurred frames a second, and it
/// means the camera is quiet between captures - so the reader's voice is
/// not competing with a detector's.
class TextReader {
  CameraController? _controller;
  TextRecognizer? _recognizer;
  bool _busy = false;

  CameraController? get controller => _controller;

  /// Asks for the camera and opens it. Returns false if refused or absent.
  Future<bool> start() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return false;

    final cameras = await availableCameras();
    if (cameras.isEmpty) return false;
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _controller = CameraController(
      back,
      // The highest the phone offers: small print on a medicine label is
      // exactly the case the tester named.
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller!.initialize();
    try {
      await _controller!.setFocusMode(FocusMode.auto);
    } catch (_) {
      // Fixed-focus camera. It will read what it can.
    }
    _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    return true;
  }

  /// Photographs whatever the camera sees and returns the words in it.
  ///
  /// Null when the camera is not open or a capture is already running;
  /// an empty string when the picture held no text.
  Future<String?> capture() async {
    final controller = _controller;
    final recognizer = _recognizer;
    if (controller == null || recognizer == null || _busy) return null;
    _busy = true;
    File? file;
    try {
      final shot = await controller.takePicture();
      file = File(shot.path);
      final result =
          await recognizer.processImage(InputImage.fromFilePath(shot.path));
      // Blocks in reading order, joined by lines: the recogniser's own
      // `text` runs blocks together for multi-column pages.
      final lines = <String>[
        for (final block in result.blocks)
          for (final line in block.lines) line.text,
      ];
      return lines.join('\n');
    } catch (_) {
      return null;
    } finally {
      _busy = false;
      // The photograph is personal data - a letter, a prescription - and it
      // has served its purpose the moment the words are out of it.
      try {
        await file?.delete();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
    await _controller?.dispose();
    _controller = null;
  }
}
