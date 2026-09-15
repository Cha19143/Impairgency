import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/vision/detection.dart';
import '../core/vision/faces.dart';
import '../core/vision/stairs.dart';
import '../core/vision/yolo.dart';
import '../core/vision/yuv_frame.dart';
import 'face_recognizer.dart';

/// Camera frames in, detections out.
///
/// The YUV handling and the rotation maths came from `cprwire` and are kept:
/// the comments about bi-planar iOS frames and sensor orientation are the
/// parts that are easy to get subtly wrong and impossible to notice.
///
/// The model underneath them is now YOLO11n rather than the SSD MobileNet that
/// was ported with them. Three things changed with it, and all three are here:
/// the input is planar and float rather than interleaved bytes, the output is
/// one raw tensor that has to be thresholded and de-duplicated in Dart, and the
/// frame is fitted into the square rather than stretched across it.
///
/// The decisions about *what to say* are still not here. They are in
/// `core/vision/detection.dart`, and the arithmetic that produces the boxes is
/// in `core/vision/yolo.dart`, where both can be tested without a camera.
class ScanService {
  /// One inference every 350 ms. Faster than a walking pace needs, and slow
  /// enough that the phone does not cook in a pocket.
  static const Duration _inferenceGap = Duration(milliseconds: 350);

  Interpreter? _interpreter;

  /// The same interpreter, driven from a background isolate.
  ///
  /// Null when one could not be started, and the synchronous path below is
  /// then used instead. That fallback is not decoration: inference at 640 is
  /// long enough to be felt, and a scan screen that runs slowly is worth
  /// vastly more than one that does not run.
  IsolateInterpreter? _worker;

  CameraController? _controller;
  bool _disposed = false;
  List<String> _labels = const [];
  int _sensorOrientation = 90;
  bool _busy = false;
  DateTime _lastInference = DateTime.fromMillisecondsSinceEpoch(0);

  /// Read off the model rather than written down here, so re-exporting it at a
  /// different size stays a one-file change.
  int _side = 0;
  int _anchors = 0;
  int _classes = kYoloClasses;

  /// The input, planar and flat.
  ///
  /// `[1, 3, side, side]`, all of red then all of green then all of blue, which
  /// is the layout this export kept from PyTorch. Flat and typed on purpose:
  /// `tflite_flutter` hands a `Uint8List` straight to the native tensor, and
  /// converts anything else element by element through a growable list — a
  /// million appends per frame, for the same bytes.
  Float32List? _input;
  Uint8List? _inputBytes;

  /// The output, taken back as raw bytes for the same reason. Read through
  /// [_output], which is a view rather than a copy.
  Uint8List? _outputBytes;
  Float32List? _output;

  Letterbox? _letterbox;

  /// The face models, loaded the first time friends are to be recognised and
  /// closed with everything else.
  FaceRecognizer? _faces;
  FaceWatch? _watch;
  DateTime _lastFaces = DateTime.fromMillisecondsSinceEpoch(0);

  /// Faces are looked for no more often than this, and only in frames with a
  /// person near enough to recognise - or while a friend is being taken
  /// down. Two more models on every frame would cook the phone.
  static const Duration _faceGap = Duration(milliseconds: 400);

  /// A person smaller than this in the frame is too far to recognise.
  static const double _minPersonExtent = 0.2;

  /// The stairs search runs no more often than this - every other frame at
  /// the model's pace. It runs on the isolate that draws the screen, where
  /// YOLO does not, so its cost is the one felt there.
  static const Duration _stairsGap = Duration(milliseconds: 500);

  /// A frame between two searches carries the last reading, this long at most:
  /// otherwise the status would flip between "stairs" and "clear" frame by
  /// frame, and so would what is said.
  static const Duration _stairsFresh = Duration(seconds: 1);

  /// Brightness for the stairs search, reused between frames. Made only when
  /// [kStairsWarnings] is on.
  late final List<List<int>> _luma = List.generate(
      kStairsGridSide, (_) => List<int>.filled(kStairsGridSide, 0));
  StairsReading _stairs = StairsReading.none;
  DateTime _stairsAt = DateTime.fromMillisecondsSinceEpoch(0);

  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized == true;

  /// Loads the model. Returns false if it could not be loaded.
  Future<bool> loadModel() async {
    try {
      final interpreter =
          await Interpreter.fromAsset('assets/models/yolo11n.tflite');

      // [1, 3, side, side] and [1, 4 + classes, anchors]. Checked rather than
      // assumed: a model whose shape is not what this code reads would
      // otherwise produce boxes instead of an error.
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;
      if (inputShape.length != 4 ||
          inputShape[1] != 3 ||
          inputShape[2] != inputShape[3] ||
          outputShape.length != 3 ||
          outputShape[1] <= kBoxRows) {
        throw StateError(
          'Unexpected model shape: input $inputShape, output $outputShape.',
        );
      }

      _side = inputShape[2];
      _classes = outputShape[1] - kBoxRows;
      _anchors = outputShape[2];

      final raw = await rootBundle.loadString('assets/models/labels.txt');
      _labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (_labels.length != _classes) {
        throw StateError(
          'The model predicts $_classes classes and labels.txt names '
          '${_labels.length}. Every box would be captioned with the wrong '
          'object.',
        );
      }

      final input = Float32List(3 * _side * _side);
      _input = input;
      _inputBytes = input.buffer.asUint8List();
      // The letterbox is a description of a buffer that has had its padding
      // written into it. This is a different buffer, so the old one no longer
      // describes anything: keeping it would leave the bars black rather than
      // the grey the model was trained to ignore.
      _letterbox = null;

      final outputBytes = Uint8List(outputShape[1] * _anchors * 4);
      _outputBytes = outputBytes;
      _output = outputBytes.buffer.asFloat32List();

      _interpreter = interpreter;
      try {
        // Off the thread that draws the screen. The camera preview is for
        // whoever is helping rather than for the user, so the jank itself is
        // not the point - blocking this isolate also delays every platform
        // message, which is what turns "Stop" into "Stop, a moment ago".
        _worker = await IsolateInterpreter.create(address: interpreter.address);
      } catch (e) {
        debugPrint('Inference stays on the UI isolate: $e');
      }
      return true;
    } catch (e) {
      debugPrint('Model load failed: $e');
      return false;
    }
  }

  /// Starts looking for faces for [watch] - loading the face models the first
  /// time - or, with null, stops. False when the models could not be loaded:
  /// this build does not have them, or this phone cannot run them.
  Future<bool> watchFaces(FaceWatch? watch) async {
    _watch = watch;
    if (watch == null || _disposed) return false;
    if (_faces != null) return true;
    final loaded = await FaceRecognizer.load();
    if (_disposed) {
      await loaded?.close();
      return false;
    }
    _faces = loaded;
    return loaded != null;
  }

  /// Asks for the camera and starts streaming. Returns false if refused.
  Future<bool> start(void Function(ScanFrame) onFrame) async {
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
      // 720x480, not the 320x240 of ResolutionPreset.low. A 640 model fed a
      // 240-pixel-wide frame spends most of its input on upscaled blur, and
      // the measurement says it costs two points of recall on nearby objects
      // and four across everything.
      //
      // It is close to free: _fillInput walks the *model's* input and samples
      // back into the camera frame, so a bigger frame does not lengthen that
      // loop. What it costs is the buffer, which is why this is medium rather
      // than the highest preset the phone will offer.
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    await _controller!.startImageStream((image) => _process(image, onFrame));
    return true;
  }

  Future<void> _process(
      CameraImage image, void Function(ScanFrame) onFrame) async {
    final interpreter = _interpreter;
    final inputBytes = _inputBytes;
    final outputBytes = _outputBytes;
    final output = _output;
    if (_disposed ||
        _busy ||
        interpreter == null ||
        inputBytes == null ||
        outputBytes == null ||
        output == null) {
      return;
    }
    if (DateTime.now().difference(_lastInference) < _inferenceGap) return;
    _busy = true;
    _lastInference = DateTime.now();

    try {
      final letterbox = _fillInput(image);

      final worker = _worker;
      if (worker != null) {
        try {
          await worker.run(inputBytes, outputBytes);
        } catch (e) {
          // One failure is enough to stop trusting it. Dropping back to the
          // inline path costs frame rate; carrying on and reading whatever is
          // in the output buffer would describe the previous frame's room, or
          // an empty one, and neither announces itself as wrong.
          debugPrint('Isolate inference failed, falling back inline: $e');
          _worker = null;
          unawaited(worker.close().catchError((_) {}));
          interpreter.run(inputBytes, outputBytes);
        }
      } else {
        interpreter.run(inputBytes, outputBytes);
      }
      // Awaiting let dispose() run. Reading the interpreter's output after it
      // has been closed is a use-after-free, not an empty frame.
      if (_disposed) return;

      final boxes = decodeYolo(
        output,
        anchors: _anchors,
        classes: _classes,
        minScore: kMinScore,
      );

      final detections = <Detection>[];
      for (final box in boxes) {
        if (box.classIndex >= _labels.length) continue;

        // Back out of the letterbox before anything reads a coordinate: these
        // have to be fractions of what the camera saw, not of the padded
        // square it was fitted into.
        final xMin = letterbox.toFrameX(box.left).clamp(0.0, 1.0);
        final xMax = letterbox.toFrameX(box.right).clamp(0.0, 1.0);
        final yMin = letterbox.toFrameY(box.top).clamp(0.0, 1.0);
        final yMax = letterbox.toFrameY(box.bottom).clamp(0.0, 1.0);
        if (xMax <= xMin || yMax <= yMin) continue;

        detections.add(detectionFrom(
          label: _labels[box.classIndex],
          score: box.score,
          xMin: xMin,
          yMin: yMin,
          xMax: xMax,
          yMax: yMax,
        ));
      }
      final frame = _uprightFrame(image);
      onFrame(ScanFrame(detections: detections, stairs: _stairsIn(frame)));
      // Inside the same busy window as the objects, so dispose() waits for
      // the face models too before closing anything.
      await _lookForFaces(frame, detections);
    } catch (e) {
      debugPrint('Detection failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// The camera's planes, readable a pixel at a time the right way up.
  YuvFrame _uprightFrame(CameraImage image) {
    final planes = image.planes;
    final biPlanar = planes.length < 3;
    return YuvFrame(
      width: image.width,
      height: image.height,
      y: planes[0].bytes,
      u: planes[1].bytes,
      v: biPlanar ? planes[1].bytes : planes[2].bytes,
      yRowStride: planes[0].bytesPerRow,
      uvRowStride: planes[1].bytesPerRow,
      uvPixelStride: planes[1].bytesPerPixel ?? (biPlanar ? 2 : 1),
      biPlanar: biPlanar,
      sensorOrientation: _sensorOrientation,
    );
  }

  /// Stairs in [frame], or the last reading while it is fresh - and never
  /// anything unless a build switched stairs warnings on.
  StairsReading _stairsIn(YuvFrame frame) {
    if (!kStairsWarnings) return StairsReading.none;
    final now = DateTime.now();
    if (now.difference(_stairsAt) >= _stairsGap) {
      fillStairsGrid(frame, _luma);
      _stairs = stairsFrom(_luma);
      _stairsAt = now;
    }
    return now.difference(_stairsAt) <= _stairsFresh
        ? _stairs
        : StairsReading.none;
  }

  Future<void> _lookForFaces(
      YuvFrame frame, List<Detection> detections) async {
    final watch = _watch;
    final faces = _faces;
    if (watch == null || faces == null || _disposed) return;
    final now = DateTime.now();
    if (now.difference(_lastFaces) < _faceGap) return;
    final people = [
      for (final d in detections)
        if (d.label == 'person' && d.extent >= _minPersonExtent && d.box != null)
          PersonBox(d.box!.left, d.box!.top, d.box!.right, d.box!.bottom),
    ];
    if (people.isEmpty && !watch.enrolling) return;
    _lastFaces = now;

    final seen = await faces.analyse(frame,
        people: people, centre: watch.enrolling, at: now);
    if (_disposed || !identical(watch, _watch)) return;
    watch.onFaces(seen);
  }

  /// Samples the frame into the model's input, rotating on the way so that x
  /// really is left-to-right *for the user* rather than for the sensor.
  ///
  /// Getting this wrong does not crash; it silently tells someone an obstacle
  /// is on their left when it is on their right.
  ///
  /// The frame is fitted whole and centred rather than stretched to the
  /// corners — see [Letterbox] for why that is worth the grey bars. The bars
  /// themselves are written once, when the geometry is first known, because
  /// they are the same in every frame.
  Letterbox _fillInput(CameraImage image) {
    final input = _input!;
    final side = _side;
    final srcW = image.width;
    final srcH = image.height;

    final quarterTurns = quarterTurnsFor(_sensorOrientation);
    final swapAxes = quarterTurns.isOdd;
    final rotW = swapAxes ? srcH : srcW;
    final rotH = swapAxes ? srcW : srcH;

    var letterbox = _letterbox;
    if (letterbox == null ||
        letterbox.frameWidth != rotW ||
        letterbox.frameHeight != rotH ||
        letterbox.side != side) {
      letterbox =
          Letterbox(frameWidth: rotW, frameHeight: rotH, side: side);
      _letterbox = letterbox;
      input.fillRange(0, input.length, Letterbox.padValue);
    }

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

    final plane = side * side;
    final drawWidth = letterbox.drawWidth;
    final drawHeight = letterbox.drawHeight;
    final padX = letterbox.padX;
    final padY = letterbox.padY;

    for (var row = 0; row < drawHeight; row++) {
      final dy = (row * rotH) ~/ drawHeight;
      final destRow = (padY + row) * side + padX;

      for (var col = 0; col < drawWidth; col++) {
        final dx = (col * rotW) ~/ drawWidth;

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
        final uvIndex = (sy ~/ 2) * uvRowStride + (sx ~/ 2) * uvPixelStride;
        final uVal = (uvIndex < uBytes.length ? uBytes[uvIndex] : 128) - 128.0;
        final vVal = (biPlanar
                ? (uvIndex + 1 < vBytes.length ? vBytes[uvIndex + 1] : 128)
                : (uvIndex < vBytes.length ? vBytes[uvIndex] : 128)) -
            128.0;

        // Planar, and scaled to 0..1: the export takes its pixels the way
        // PyTorch left them, not the way a camera hands them over.
        final at = destRow + col;
        input[at] = ((yVal + 1.402 * vVal) / 255).clamp(0.0, 1.0);
        input[plane + at] =
            ((yVal - 0.344136 * uVal - 0.714136 * vVal) / 255).clamp(0.0, 1.0);
        input[2 * plane + at] = ((yVal + 1.772 * uVal) / 255).clamp(0.0, 1.0);
      }
    }

    return letterbox;
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _controller?.stopImageStream();
    } catch (_) {
      // Already stopped, or never started.
    }
    await _controller?.dispose();
    _controller = null;

    // A run that has not returned still has the interpreter's memory in hand
    // on the worker's thread. Closing the interpreter under it is a SIGSEGV
    // in libtensorflowlite_jni, not an exception the caller could catch: the
    // app died on the scan screen's Back button, mid-inference. The stream is
    // stopped above, so nothing new starts; wait for what is already running,
    // and give up on it after two seconds rather than hang the screen.
    var waited = 0;
    while (_busy && waited < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      waited++;
    }

    // The worker holds the interpreter by address, so it has to be stopped
    // before the interpreter is closed under it.
    await _worker?.close();
    _worker = null;
    _interpreter?.close();
    _interpreter = null;
    _watch = null;
    await _faces?.close();
    _faces = null;
  }

  /// Exposed so a test can check the maths without a camera.
  @visibleForTesting
  static int quarterTurnsFor(int sensorOrientation) =>
      ((sensorOrientation ~/ 90) % 4 + 4) % 4;
}
