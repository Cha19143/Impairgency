import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/vision/blazeface.dart';
import '../core/vision/face_align.dart';
import '../core/vision/faces.dart';
import '../core/vision/yuv_frame.dart';

/// MediaPipe's BlazeFace, short range.
const String kFaceDetectorAsset =
    'assets/models/face_detection_short_range.tflite';

/// MobileFaceNet: a face in, a short list of numbers out.
const String kFaceEmbedderAsset = 'assets/models/mobilefacenet.tflite';

/// A person the object detector boxed, as fractions of the upright frame.
class PersonBox {
  const PersonBox(this.left, this.top, this.right, this.bottom);
  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// Faces in a camera frame, as numbers that can be compared.
///
/// Two small models, run only when the scan service asks - a person close
/// enough to recognise, or a friend being taken down - and never on the
/// camera's every frame. Each keeps its buffers for the life of the
/// recogniser, for the same reason the scan service does: `tflite_flutter`
/// copies typed bytes straight across, and anything else element by element.
///
/// Nothing here keeps a picture or a face. [analyse] hands back numbers and
/// forgets the frame; deciding whose they are is `core/vision/faces.dart`.
class FaceRecognizer {
  FaceRecognizer._({
    required Interpreter detector,
    required Interpreter embedder,
    required IsolateInterpreter? detectorWorker,
    required IsolateInterpreter? embedderWorker,
    required int regressorsIndex,
    required int scoresIndex,
    required int embeddingLength,
  })  : _detector = detector,
        _embedder = embedder,
        _detectorWorker = detectorWorker,
        _embedderWorker = embedderWorker,
        _regressorsIndex = regressorsIndex,
        _scoresIndex = scoresIndex,
        _detectorInput = Float32List(kBlazeFaceSide * kBlazeFaceSide * 3),
        _regressorBytes = Uint8List(kBlazeFaceAnchors * kBlazeFaceCoords * 4),
        _scoreBytes = Uint8List(kBlazeFaceAnchors * 4),
        _embedderInput = Float32List(kFaceCropSide * kFaceCropSide * 3),
        _embeddingBytes = Uint8List(embeddingLength * 4);

  final Interpreter _detector;
  final Interpreter _embedder;
  IsolateInterpreter? _detectorWorker;
  IsolateInterpreter? _embedderWorker;
  final int _regressorsIndex;
  final int _scoresIndex;

  final Float32List _detectorInput;
  final Uint8List _regressorBytes;
  final Uint8List _scoreBytes;
  final Float32List _embedderInput;
  final Uint8List _embeddingBytes;

  bool _closed = false;

  /// Both models, checked against the shapes this code reads - or null, with
  /// the reason in the log. A build without the model files still runs; it
  /// just cannot recognise anyone, and says so.
  static Future<FaceRecognizer?> load() async {
    Interpreter? detector;
    Interpreter? embedder;
    try {
      detector = await Interpreter.fromAsset(kFaceDetectorAsset);
      embedder = await Interpreter.fromAsset(kFaceEmbedderAsset);

      final detectorIn = detector.getInputTensor(0).shape;
      if (detectorIn.length != 4 ||
          detectorIn[1] != kBlazeFaceSide ||
          detectorIn[2] != kBlazeFaceSide ||
          detectorIn[3] != 3) {
        throw StateError('Face detector input is $detectorIn.');
      }
      var regressors = -1;
      var scores = -1;
      final outputs = detector.getOutputTensors();
      for (var i = 0; i < outputs.length; i++) {
        final shape = outputs[i].shape;
        if (shape.length != 3 || shape[1] != blazeFaceAnchorCount) continue;
        if (shape[2] == kBlazeFaceCoords) regressors = i;
        if (shape[2] == 1) scores = i;
      }
      if (regressors < 0 || scores < 0) {
        throw StateError('Face detector outputs are '
            '${outputs.map((o) => o.shape).toList()}.');
      }

      final embedderIn = embedder.getInputTensor(0).shape;
      final embedderOut = embedder.getOutputTensor(0).shape;
      if (embedderIn.length != 4 ||
          embedderIn[1] != kFaceCropSide ||
          embedderIn[2] != kFaceCropSide ||
          embedderIn[3] != 3 ||
          embedderOut.length != 2) {
        throw StateError(
            'Face recogniser is $embedderIn to $embedderOut.');
      }

      IsolateInterpreter? detectorWorker;
      IsolateInterpreter? embedderWorker;
      try {
        detectorWorker =
            await IsolateInterpreter.create(address: detector.address);
        embedderWorker =
            await IsolateInterpreter.create(address: embedder.address);
      } catch (e) {
        debugPrint('Face models stay on the UI isolate: $e');
      }
      return FaceRecognizer._(
        detector: detector,
        embedder: embedder,
        detectorWorker: detectorWorker,
        embedderWorker: embedderWorker,
        regressorsIndex: regressors,
        scoresIndex: scores,
        embeddingLength: embedderOut[1],
      );
    } catch (e) {
      debugPrint('Face models not loaded: $e');
      detector?.close();
      embedder?.close();
      return null;
    }
  }

  /// Faces in [frame]: around the heads of [people], and in the middle of the
  /// frame when [centre] - someone is being taken down. Two faces a square at
  /// most, and one face found from two squares counted once.
  Future<List<FaceObservation>> analyse(
    YuvFrame frame, {
    List<PersonBox> people = const [],
    bool centre = false,
    required DateTime at,
  }) async {
    if (_closed) return const [];
    final squares = [
      if (centre) centreSquare(frame),
      for (final p in people.take(2))
        headSquare(frame,
            left: p.left, top: p.top, right: p.right, bottom: p.bottom),
    ];

    final found = <(FaceObservation, double)>[];
    for (final square in squares) {
      fillSquare(frame, square, _detectorInput,
          side: kBlazeFaceSide, scale: 2 / 255, shift: -1);
      await _run(_detector, _detectorWorker, _detectorInput.buffer.asUint8List(),
          {_regressorsIndex: _regressorBytes, _scoresIndex: _scoreBytes},
          detector: true);
      if (_closed) return const [];
      final faces = decodeBlazeFace(_regressorBytes.buffer.asFloat32List(),
          _scoreBytes.buffer.asFloat32List());

      for (final face in faces.take(2)) {
        final centreX = square.left + face.centerX * square.size;
        final width = face.width * square.size;
        if (found.any((f) =>
            (f.$2 - centreX).abs() < width / 2)) {
          continue;
        }
        final toCrop = alignFace(face, (p) => square.toFrame(p.x, p.y));
        fillAligned(frame, toCrop, _embedderInput,
            scale: 1 / 128, shift: -127.5 / 128);
        await _run(_embedder, _embedderWorker,
            _embedderInput.buffer.asUint8List(), {0: _embeddingBytes},
            detector: false);
        if (_closed) return const [];
        found.add((
          FaceObservation(
            embedding: l2Normalize(
                _embeddingBytes.buffer.asFloat32List().toList()),
            width: width / frame.uprightWidth,
            centerX: centreX / frame.uprightWidth,
            rollDegrees: face.rollDegrees,
            at: at,
          ),
          centreX,
        ));
      }
    }
    return [for (final f in found) f.$1];
  }

  Future<void> _run(Interpreter interpreter, IsolateInterpreter? worker,
      Uint8List input, Map<int, Object> outputs,
      {required bool detector}) async {
    if (worker != null) {
      try {
        await worker.runForMultipleInputs([input], outputs);
        return;
      } catch (e) {
        debugPrint('Isolate face inference failed, falling back inline: $e');
        if (detector) {
          _detectorWorker = null;
        } else {
          _embedderWorker = null;
        }
        await worker.close().catchError((_) {});
      }
    }
    if (_closed) return;
    interpreter.runForMultipleInputs([input], outputs);
  }

  /// Only once nothing is running: the scan service waits for its frame to
  /// finish before calling this, as it does for its own model.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _detectorWorker?.close();
    await _embedderWorker?.close();
    _detectorWorker = null;
    _embedderWorker = null;
    _detector.close();
    _embedder.close();
  }
}
