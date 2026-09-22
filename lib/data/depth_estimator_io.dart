import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/vision/depth.dart';
import '../core/vision/yuv_frame.dart';

/// What MiDaS was trained on, per channel: pixels are scaled to 0..1, then
/// normalised with ImageNet's means and deviations.
const List<double> _mean = [0.485, 0.456, 0.406];
const List<double> _deviation = [0.229, 0.224, 0.225];

/// A camera frame in, how near each part of it is out.
class DepthEstimator {
  DepthEstimator._(this._interpreter, this._worker)
      : _input = Float32List(kDepthSide * kDepthSide * 3),
        _outputBytes = Uint8List(kDepthSide * kDepthSide * 4);

  final Interpreter _interpreter;
  IsolateInterpreter? _worker;
  final Float32List _input;
  final Uint8List _outputBytes;
  bool _closed = false;

  /// The model, checked against the shape this code reads - or null, with
  /// the reason in the log. A build without the file runs as before.
  static Future<DepthEstimator?> load() async {
    Interpreter? interpreter;
    try {
      interpreter = await Interpreter.fromAsset(kDepthModelAsset);
      final input = interpreter.getInputTensor(0).shape;
      final output = interpreter.getOutputTensor(0).shape;
      final outputOk = (output.length == 3 &&
              output[1] == kDepthSide &&
              output[2] == kDepthSide) ||
          (output.length == 4 &&
              output[1] == kDepthSide &&
              output[2] == kDepthSide &&
              output[3] == 1);
      if (input.length != 4 ||
          input[1] != kDepthSide ||
          input[2] != kDepthSide ||
          input[3] != 3 ||
          !outputOk) {
        throw StateError('Depth model is $input to $output.');
      }
      IsolateInterpreter? worker;
      try {
        worker = await IsolateInterpreter.create(address: interpreter.address);
      } catch (e) {
        debugPrint('Depth stays on the UI isolate: $e');
      }
      return DepthEstimator._(interpreter, worker);
    } catch (e) {
      debugPrint('Depth model not loaded: $e');
      interpreter?.close();
      return null;
    }
  }

  /// How near each part of [frame] is: the middle square of it, the size of
  /// its shorter side.
  Future<DepthReading> estimate(YuvFrame frame) async {
    if (_closed) return DepthReading.none;
    final shorter = frame.uprightWidth < frame.uprightHeight
        ? frame.uprightWidth
        : frame.uprightHeight;
    final square = FrameSquare((frame.uprightWidth - shorter) / 2,
        (frame.uprightHeight - shorter) / 2, shorter.toDouble());
    fillSquare(frame, square, _input,
        side: kDepthSide, scale: 1 / 255, shift: 0);
    for (var at = 0; at < _input.length; at += 3) {
      for (var channel = 0; channel < 3; channel++) {
        _input[at + channel] =
            (_input[at + channel] - _mean[channel]) / _deviation[channel];
      }
    }

    final inputBytes = _input.buffer.asUint8List();
    final worker = _worker;
    if (worker != null) {
      try {
        await worker.run(inputBytes, _outputBytes);
      } catch (e) {
        debugPrint('Isolate depth failed, falling back inline: $e');
        _worker = null;
        await worker.close().catchError((_) {});
        _interpreter.run(inputBytes, _outputBytes);
      }
    } else {
      _interpreter.run(inputBytes, _outputBytes);
    }
    // Awaiting let close() run; the output is not to be read after it.
    if (_closed) return DepthReading.none;
    return depthFrom(_outputBytes.buffer.asFloat32List());
  }

  Future<void> close() async {
    _closed = true;
    await _worker?.close();
    _worker = null;
    _interpreter.close();
  }
}
