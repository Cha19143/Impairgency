import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/vision/detection.dart';
import 'package:impairgency/vi/surroundings_watch.dart';

import 'screens/scan_fakes.dart';

/// A camera that throws the first [failures] times it is asked for - still
/// held by the screen before - and opens after that.
class BusyCamera extends FakeScan {
  BusyCamera(this.failures);
  int failures;

  @override
  Future<bool> start(void Function(ScanFrame) onFrame) async {
    starts++;
    if (failures > 0) {
      failures--;
      throw PlatformException(code: 'CameraAccess', message: 'in use');
    }
    this.onFrame = onFrame;
    return true;
  }
}

class RefusedCamera extends FakeScan {
  @override
  Future<bool> start(void Function(ScanFrame) onFrame) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a camera still held by the last screen is asked for again', () async {
    // Scan hands the camera to the journey screen, and the journey screen
    // back to Scan: the one closing may not have let go yet.
    final speaker = RecordingSpeaker();
    final camera = BusyCamera(1);
    final waits = <Duration>[];
    final watch = SurroundingsWatch(
      speaker: speaker,
      service: camera,
      wait: (delay) async => waits.add(delay),
    );

    await watch.start(readyPhrase: 'Guidance ready.');

    expect(camera.starts, 2);
    expect(waits, [kCameraRetryGap]);
    expect(watch.ready, isTrue);
    expect(speaker.said.last.$1, 'Guidance ready.');
    watch.dispose();
  });

  test('a camera that will not open says so, rather than starting for ever',
      () async {
    final speaker = RecordingSpeaker();
    final watch = SurroundingsWatch(
      speaker: speaker,
      service: BusyCamera(2),
      wait: (_) async {},
    );

    await watch.start(readyPhrase: 'Guidance ready.');

    expect(watch.ready, isFalse);
    expect(watch.failed, isTrue);
    expect(watch.guidance, 'The camera could not start.');
    expect(speaker.said.last.$1, startsWith('The camera could not start.'));
    watch.dispose();
  });

  test('a refused camera says where to turn it on', () async {
    final speaker = RecordingSpeaker();
    final watch =
        SurroundingsWatch(speaker: speaker, service: RefusedCamera());

    await watch.start(readyPhrase: 'Guidance ready.');

    expect(watch.refused, isTrue);
    expect(speaker.said.last.$1, contains('Turn it on in Settings'));
    watch.dispose();
  });

  test('a close obstacle is a hazard, and named for the guardian', () async {
    final speaker = RecordingSpeaker();
    final camera = FakeScan();
    final named = <String>[];
    final watch = SurroundingsWatch(
        speaker: speaker, service: camera, onObstacle: named.add);
    await watch.start(readyPhrase: 'Guidance ready.');

    camera.see(const [
      Detection(label: 'car', score: 0.9, centerX: 0.5, extent: 0.7),
    ]);

    expect(speaker.said.last.$2, SpeechPriority.hazard);
    expect(named, ['car']);
    expect(watch.guidance, speaker.said.last.$1);
    watch.dispose();
  });

  test('nothing is said once the screen has gone', () async {
    final speaker = RecordingSpeaker();
    final camera = FakeScan();
    final watch = SurroundingsWatch(speaker: speaker, service: camera);
    await watch.start(readyPhrase: 'Guidance ready.');
    final before = speaker.said.length;

    watch.dispose();
    camera.see(const [
      Detection(label: 'car', score: 0.9, centerX: 0.5, extent: 0.7),
    ]);
    expect(speaker.said, hasLength(before));
  });
}
