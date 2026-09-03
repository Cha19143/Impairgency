import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/vision/detection.dart';

/// Camera frames in, detections out.
///
/// Ported from `cprwire`, whose YUV handling and rotation maths were correct
/// and hard-won — the comments about bi-planar iOS frames and sensor
/// orientation are kept because they are the parts that are easy to get subtly
/// wrong and impossible to notice.
///
/// The decisions about *what to say* are not here. They are in
/// `core/vision/detection.dart`, where they can be tested without a camera.
class ScanService {
  static const int _inputSize = 300;
  static const int _maxDetections = 10;

  /// One inference every 350 ms. Faster than a walking pace needs, and slow
  /// enough that the phone does not cook in a pocket.
  static const Duration _inferenceGap = Duration(milliseconds: 350);

  Interpreter? _interpreter;
  CameraController? _controller;
  List<String> _labels = const [];
  int _sensorOrientation = 90;
  bool _busy = false;
  DateTime _lastInference = DateTime.fromMillisecondsSinceEpoch(0);

  late final List<List<List<List<int>>>> _input = [
    List.generate(
      _inputSize,
      (_) => List.generate(_inputSize, (_) => List.filled(3, 0)),
    )
  ];
  final _outBoxes = [
    List.generate(_maxDetections, (_) => List.filled(4, 0.0))
  ];
  final _outClasses = [List.filled(_maxDetections, 0.0)];
  final _outScores = [List.filled(_maxDetections, 0.0)];
  final _outCount = [0.0];

  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized == true;

  /// Loads the model. Returns false if it could not be loaded.
  Future<bool> loadModel() async {
    try {
      _interpreter =
          await Interpreter.fromAsset('assets/models/ssd_mobilenet.tflite');
      final raw = await rootBundle.loadString('assets/models/labels.txt');
      _labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return true;
    } catch (e) {
      debugPrint('Model load failed: $e');
      return false;
    }
  }

  /// Asks for the camera and starts streaming. Returns false if refused.
  Future<bool> start(void Function(List<Detection>) onFrame) async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return false;

    final cameras = await availableCameras();
    if (cameras.isEmpty) return false;
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _sensorOrientation = back.sensorOrientation;

    _controller = CameraController(
      back,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    await _controller!.startImageStream((image) => _process(image, onFrame));
    return true;
  }

  void _process(CameraImage image, void Function(List<Detection>) onFrame) {
    if (_busy || _interpreter == null) return;
    if (DateTime.now().difference(_lastInference) < _inferenceGap) return;
    _busy = true;
    _lastInference = DateTime.now();

    try {
      _fillInput(image);
      _interpreter!.runForMultipleInputs([_input], {
        0: _outBoxes,
        1: _outClasses,
        2: _outScores,
        3: _outCount,
      });

      final detections = <Detection>[];
      // Not gated on the num_detections output: some SSD exports leave it at
      // zero, and the score threshold already filters the empty slots.
      for (var i = 0; i < _maxDetections; i++) {
        final score = _outScores[0][i];
        if (score < kMinScore) continue;

        final classIndex = _outClasses[0][i].toInt();
        if (classIndex < 0 || classIndex >= _labels.length) continue;

        // SSD box layout is [yMin, xMin, yMax, xMax], normalised.
        final box = _outBoxes[0][i];
        final yMin = box[0].clamp(0.0, 1.0);
        final xMin = box[1].clamp(0.0, 1.0);
        final yMax = box[2].clamp(0.0, 1.0);
        final xMax = box[3].clamp(0.0, 1.0);
        if (xMax <= xMin || yMax <= yMin) continue;

        detections.add(detectionFrom(
          label: _labels[classIndex],
          score: score,
          xMin: xMin,
          yMin: yMin,
          xMax: xMax,
          yMax: yMax,
        ));
      }
      onFrame(detections);
    } catch (e) {
      debugPrint('Detection failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// Samples the frame straight into the model's input, rotating on the way so
  /// that x really is left-to-right *for the user* rather than for the sensor.
  ///
  /// Getting this wrong does not crash; it silently tells someone an obstacle
  /// is on their left when it is on their right.
  void _fillInput(CameraImage image) {
    final srcW = image.width;
    final srcH = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    // iOS hands back bi-planar NV12 (two planes, U and V interleaved);
    // Android gives three separate planes.
    final biPlanar = image.planes.length < 3;
    final vPlane = biPlanar ? uPlane : image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? (biPlanar ? 2 : 1);

    final quarterTurns = ((_sensorOrientation ~/ 90) % 4 + 4) % 4;
    final swapAxes = quarterTurns.isOdd;
    final rotW = swapAxes ? srcH : srcW;
    final rotH = swapAxes ? srcW : srcH;

    for (var my = 0; my < _inputSize; my++) {
      final dy = (my * rotH) ~/ _inputSize;
      final row = _input[0][my];

      for (var mx = 0; mx < _inputSize; mx++) {
        final dx = (mx * rotW) ~/ _inputSize;

        int sx;
        int sy;
        switch (quarterTurns) {
          case 1:
            sx = dy;
            sy = srcH - 1 - dx;
          case 2:
            sx = srcW - 1 - dx;
            sy = srcH - 1 - dy;
          case 3:
            sx = srcW - 1 - dy;
            sy = dx;
          default:
            sx = dx;
            sy = dy;
        }
        sx = sx.clamp(0, srcW - 1);
        sy = sy.clamp(0, srcH - 1);

        final yVal = yBytes[sy * yRowStride + sx].toDouble();
        final uvIndex =
            (sy ~/ 2) * uvRowStride + (sx ~/ 2) * uvPixelStride;
        final uVal = (uvIndex < uBytes.length ? uBytes[uvIndex] : 128) - 128.0;
        final vVal = (biPlanar
                ? (uvIndex + 1 < vBytes.length ? vBytes[uvIndex + 1] : 128)
                : (uvIndex < vBytes.length ? vBytes[uvIndex] : 128)) -
            128.0;

        final px = row[mx];
        px[0] = (yVal + 1.402 * vVal).round().clamp(0, 255);
        px[1] = (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
        px[2] = (yVal + 1.772 * uVal).round().clamp(0, 255);
      }
    }
  }

  Future<void> dispose() async {
    try {
      await _controller?.stopImageStream();
    } catch (_) {
      // Already stopped, or never started.
    }
    await _controller?.dispose();
    _controller = null;
    _interpreter?.close();
    _interpreter = null;
  }

  /// Exposed so a test can check the maths without a camera.
  @visibleForTesting
  static int quarterTurnsFor(int sensorOrientation) =>
      ((sensorOrientation ~/ 90) % 4 + 4) % 4;

  @visibleForTesting
  static double maxSide(double w, double h) => math.max(w, h);
}
