import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/vision/detection.dart';
import '../core/vision/stairs.dart';
import '../core/vision/yolo.dart';
import '../core/vision/yuv_frame.dart';

/// A camera frame in, the stairs in it out: the single-class YOLO11n trained
/// for them, beside the COCO model.
class StairsDetector {
  StairsDetector._(this._interpreter, this._worker, this._anchors)
      : _input = Float32List(3 * kStairsSide * kStairsSide),
        _outputBytes = Uint8List((kBoxRows + 1) * _anchors * 4);

  final Interpreter _interpreter;
  IsolateInterpreter? _worker;
  final int _anchors;
  final Float32List _input;
  final Uint8List _outputBytes;
  Letterbox? _letterbox;
  bool _closed = false;

  /// The model, checked against the shape this code reads - or null, with
  /// the reason in the log. A build without the file runs as before and says
  /// nothing about stairs.
  static Future<StairsDetector?> load() async {
    Interpreter? interpreter;
    try {
      interpreter = await Interpreter.fromAsset(kStairsModelAsset);
      final input = interpreter.getInputTensor(0).shape;
      final output = interpreter.getOutputTensor(0).shape;
      if (input.length != 4 ||
          input[1] != 3 ||
          input[2] != kStairsSide ||
          input[3] != kStairsSide ||
          output.length != 3 ||
          output[1] != kBoxRows + 1) {
        throw StateError('Stairs model is $input to $output.');
      }
      IsolateInterpreter? worker;
      try {
        worker = await IsolateInterpreter.create(address: interpreter.address);
      } catch (e) {
        debugPrint('Stairs stay on the UI isolate: $e');
      }
      return StairsDetector._(interpreter, worker, output[2]);
    } catch (e) {
      debugPrint('Stairs model not loaded: $e');
      interpreter?.close();
      return null;
    }
  }

  /// The stairs in [frame], as detections of it.
  Future<List<Detection>> detect(YuvFrame frame) async {
    if (_closed) return const [];
    var box = _letterbox;
    if (box == null ||
        box.frameWidth != frame.uprightWidth ||
        box.frameHeight != frame.uprightHeight) {
      box = _letterbox = Letterbox(
          frameWidth: frame.uprightWidth,
          frameHeight: frame.uprightHeight,
          side: kStairsSide);
    }
    fillLetterboxed(frame, box, _input);

    final inputBytes = _input.buffer.asUint8List();
    final worker = _worker;
    if (worker != null) {
      try {
        await worker.run(inputBytes, _outputBytes);
      } catch (e) {
        debugPrint('Isolate stairs failed, falling back inline: $e');
        _worker = null;
        await worker.close().catchError((_) {});
        _interpreter.run(inputBytes, _outputBytes);
      }
    } else {
      _interpreter.run(inputBytes, _outputBytes);
    }
    // Awaiting let close() run; the output is not to be read after it.
    if (_closed) return const [];
    final raw = decodeYolo(
      _outputBytes.buffer.asFloat32List(),
      anchors: _anchors,
      classes: 1,
      minScore: kStairsSoft,
    );
    return stairsDetections(raw, box);
  }

  Future<void> close() async {
    _closed = true;
    await _worker?.close();
    _worker = null;
    _interpreter.close();
  }
}
