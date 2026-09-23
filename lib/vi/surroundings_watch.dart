import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/speech/speaker.dart';
import '../core/vision/detection.dart';
import '../core/vision/faces.dart';
import '../core/vision/friend_recognition.dart';
import '../core/vision/stairs.dart' show kStairsLabel;
import '../core/voice/voice_commands.dart';
import '../data/scan_service.dart';
import 'voice_controller.dart';

/// How long to wait before asking for the camera a second time. The screen
/// before may still be letting go of it: Scan hands the camera to the journey
/// screen, and the journey screen back to Scan.
const Duration kCameraRetryGap = Duration(milliseconds: 700);

/// What is in front of the user: the camera, the model, the warnings, and the
/// friends it knows.
///
/// Scan describes the surroundings; the journey screen gives directions. Both
/// warn about obstacles and people while they are open, and a warning must
/// not depend on which of them is showing - so the watching is one thing, and
/// each screen has one of its own.
class SurroundingsWatch extends ChangeNotifier {
  SurroundingsWatch({
    required this.speaker,
    ScanService? service,
    this.voice,
    FriendRecognition? friends,
    this.onObstacle,
    Future<void> Function(Duration delay)? wait,
  })  : service = service ?? ScanService(),
        _friends = friends,
        _wait = wait ?? ((delay) => Future<void>.delayed(delay));

  /// Takes priorities: a hazard and something else can need saying at once.
  final PrioritySpeaker speaker;

  final ScanService service;
  final VoiceController? voice;

  /// Something close enough to walk into was warned about, by name. The
  /// session tells the guardian, if the user said it may.
  final void Function(String label)? onObstacle;

  final FriendRecognition? _friends;
  final Future<void> Function(Duration delay) _wait;

  /// What the camera last showed, in the words that were said.
  String get guidance => _guidance;
  String _guidance = 'Starting…';

  /// The camera and the model are running.
  bool get ready => _ready;
  bool _ready = false;

  /// The camera permission was refused.
  bool get refused => _refused;
  bool _refused = false;

  /// The camera would not open, twice.
  bool get failed => _failed;
  bool _failed = false;

  CameraController? get camera => _ready ? service.controller : null;

  FaceWatch? _faceWatch;
  bool _facesReady = false;

  /// Whether the face models have been asked to start: until then, "not
  /// ready" means the camera is still starting, not that they failed.
  bool _facesTried = false;

  String? _lastPhrase;
  DateTime? _lastSpokenAt;
  bool _disposed = false;

  /// Starts the model and the camera, then says [readyPhrase] - and meets
  /// [meetFriend], if someone asked to be remembered on another screen.
  Future<void> start({required String readyPhrase, String? meetFriend}) async {
    final modelOk = await service.loadModel();
    if (_disposed) return;
    if (!modelOk) {
      _show('Guidance is not available.');
      await speaker.speak(
          'Sorry, guidance could not start. Everything else still works.');
      return;
    }

    final bool cameraOk;
    try {
      cameraOk = await _startCamera();
    } catch (e) {
      debugPrint('The camera would not start: $e');
      if (_disposed) return;
      _failed = true;
      _show('The camera could not start.');
      await speaker.speak('The camera could not start. Go back, and open '
          'this screen again.');
      return;
    }
    if (_disposed) return;
    if (!cameraOk) {
      _refused = true;
      _show('The camera is off.');
      await speaker.speak('The camera is turned off for this app. Turn it on '
          'in Settings to use guidance.');
      return;
    }

    _ready = true;
    _show(kNoKnownObjects);

    final friends = _friends;
    if (friends != null) {
      await friends.load();
      if (_disposed) return;
      final watch = _faceWatch = FaceWatch(onFaces: friends.onFaces);
      _facesReady = await service.watchFaces(watch);
      _facesTried = true;
      if (_disposed) return;
    }
    await speaker.speak(readyPhrase);
    if (meetFriend != null && !_disposed) unawaited(meet(meetFriend));
  }

  /// The camera, asked for once more after [kCameraRetryGap] if it throws.
  Future<bool> _startCamera() async {
    try {
      return await service.start(onFrame);
    } catch (e) {
      debugPrint('The camera would not start, trying again: $e');
      await _wait(kCameraRetryGap);
      if (_disposed) return false;
      return service.start(onFrame);
    }
  }

  void _show(String guidance) {
    _guidance = guidance;
    if (!_disposed) notifyListeners();
  }

  /// One frame from the camera.
  void onFrame(ScanFrame frame) {
    if (_disposed) return;
    final notice = frame.notice;
    if (notice != null) {
      speaker.announce(notice, priority: SpeechPriority.info);
    }
    final guidance = guidanceFor(frame.detections, depth: frame.depth);
    _show(guidance.phrase);
    // While a friend's face is being taken down, "person ahead" is the friend.
    // Only a hazard interrupts.
    if ((_faceWatch?.enrolling ?? false) && !guidance.urgent) return;

    final now = DateTime.now();
    if (!shouldSpeak(
      phrase: guidance.phrase,
      urgent: guidance.urgent,
      quiet: guidance.nothingSeen,
      lastPhrase: _lastPhrase,
      lastSpokenAt: _lastSpokenAt,
      now: now,
    )) {
      return;
    }
    _lastPhrase = guidance.phrase;
    _lastSpokenAt = now;
    // A buzz as well as a word: someone in traffic may not hear it.
    if (guidance.urgent) HapticFeedback.heavyImpact();
    // Stairs are told to the guardian and kept on the journey whenever they
    // are said, "Stop" or not: a flight of stairs is worth knowing about.
    final stairs = guidance.label == kStairsLabel;
    if ((guidance.urgent || stairs) && guidance.label != null) {
      onObstacle?.call(guidance.label!);
    }
    // Hazards preempt whatever else is being said and are never restarted
    // while still in progress; ordinary descriptions wait their turn. The
    // queue holds that rule, not this. Stairs short of a "Stop" wait too, but
    // are not dropped by the next thing said, as a description would be.
    speaker.announce(
      guidance.phrase,
      priority: guidance.urgent
          ? SpeechPriority.hazard
          : stairs
              ? SpeechPriority.navigation
              : SpeechPriority.info,
    );
  }

  /// The friend commands, which mean the same on every screen that watches.
  /// Returns false for anything else.
  Future<bool> handleVoice(ParsedCommand heard) async {
    switch (heard.command) {
      case VoiceCommand.rememberFriend:
        await meet(heard.argument ?? '');
        return true;
      case VoiceCommand.whoIsHere:
        final friends = _friends;
        await speaker.speak(friends == null
            ? kFacesOffPhrase
            : !_facesReady
                ? _facesProblem
                : friends.whoIsHere());
        return true;
      case VoiceCommand.listFriends:
        final friends = _friends;
        if (friends == null) return false;
        await speaker.speak(friends.list());
        return true;
      case VoiceCommand.forgetAllFriends:
        // Here, not app-wide: this screen's recognition holds the faces in
        // memory, and would go on naming people until it was left.
        final friends = _friends;
        final voice = this.voice;
        if (friends == null || voice == null) return false;
        final saved = [...friends.friends];
        if (saved.isEmpty) {
          await speaker.speak('No one is saved, so nothing changed.');
          return true;
        }
        final answer = await voice.ask('Forget everyone saved? All '
            '${saved.length} faces will be deleted from this phone. Say yes '
            'to forget them.');
        if (answer?.command != VoiceCommand.yes) {
          await speaker.speak('Nothing was deleted.');
          return true;
        }
        for (final friend in saved) {
          await friends.remove(friend);
        }
        await speaker.speak('Everyone is forgotten.');
        return true;
      case VoiceCommand.renameFriend:
        final friends = _friends;
        if (friends == null) return false;
        final parts = renameParts(heard.argument ?? '');
        await speaker.speak(parts == null
            ? 'Say rename, their name, to, and the new name.'
            : await friends.rename(parts.$1, parts.$2));
        return true;
      case VoiceCommand.forgetFriend:
        final friends = _friends;
        final voice = this.voice;
        // Without recognition on, the app-wide handler still deletes a face
        // saved earlier.
        if (friends == null || voice == null) return false;
        await speaker
            .speak(await friends.forget(heard.argument ?? '', ask: voice.ask));
        return true;
      default:
        return false;
    }
  }

  /// "Hello friend Sam": asks Sam, then takes Sam's face down.
  ///
  /// The question is for the friend, and it is asked out loud with them in
  /// front of the phone: it is their face. No, or no answer, and nothing is
  /// kept.
  Future<void> meet(String rawName) async {
    final name = normaliseFriendName(rawName);
    final friends = _friends;
    final voice = this.voice;
    final watch = _faceWatch;
    if (name == null) {
      await speaker.speak('Say hello friend, and then their name.');
      return;
    }
    if (friends == null) {
      await speaker.speak(kFacesOffPhrase);
      return;
    }
    if (!_facesReady || watch == null || voice == null) {
      await speaker.speak(_facesProblem);
      return;
    }
    final answer = await voice.ask(friendConsentQuestion(name));
    if (_disposed) return;
    if (answer?.command != VoiceCommand.yes) {
      await speaker.speak('Nothing was saved.');
      return;
    }
    await speaker.speak(
        "Point the phone at $name's face, about an arm's length away, and "
        'hold still.');
    if (_disposed) return;
    watch.enrolling = true;
    notifyListeners();
    final result = await friends.enrol(name);
    if (_disposed) return;
    watch.enrolling = false;
    notifyListeners();
    await speaker.speak(enrollmentResultPhrase(result, name: name));
  }

  /// Why friends cannot be recognised right now, said as it is.
  String get _facesProblem => _failed || _refused
      ? kFacesNoCameraPhrase
      : !_facesTried
          ? kFacesStartingPhrase
          : kFacesModelsMissingPhrase;

  @override
  void dispose() {
    _disposed = true;
    // The service waits for a frame in progress before letting the camera go.
    unawaited(service.dispose());
    super.dispose();
  }
}
