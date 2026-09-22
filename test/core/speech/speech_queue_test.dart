import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/speech/speech_queue.dart';

/// An engine that only finishes a sentence when the test says so.
///
/// The queue's whole job is deciding what happens *while* something is being
/// said, so the test has to be able to hold a sentence open.
class FakeEngine implements SpeechEngine {
  final List<String> started = [];
  final List<String> finished = [];
  final List<String> cutOff = [];
  Completer<void>? _active;
  String? _activeText;

  String? get speaking => _activeText;

  @override
  Future<void> say(String text) {
    started.add(text);
    _activeText = text;
    _active = Completer<void>();
    return _active!.future;
  }

  /// The engine reached the end of the sentence on its own.
  void complete() {
    final text = _activeText;
    final active = _active;
    _activeText = null;
    _active = null;
    if (text != null) finished.add(text);
    active?.complete();
  }

  @override
  Future<void> stop() async {
    final text = _activeText;
    final active = _active;
    _activeText = null;
    _active = null;
    if (text != null) cutOff.add(text);
    active?.complete();
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeEngine engine;
  late SpeechQueue queue;

  setUp(() {
    engine = FakeEngine();
    queue = SpeechQueue(engine: engine, lineGap: Duration.zero);
  });

  group('the tester\'s bug: a warning must be heard end to end', () {
    test('the same hazard arriving again does not restart the sentence',
        () async {
      const warning = 'Stop. tree right in front of you';
      unawaited(queue.announce(warning, priority: SpeechPriority.hazard));
      await settle();
      // The next ten camera frames all say the same thing.
      for (var i = 0; i < 10; i++) {
        unawaited(queue.announce(warning, priority: SpeechPriority.hazard));
      }
      await settle();

      expect(engine.started, [warning], reason: 'started once');
      expect(engine.cutOff, isEmpty, reason: 'never interrupted');
      expect(queue.pending, isEmpty, reason: 'and not queued up ten times');

      engine.complete();
      await settle();
      expect(engine.finished, [warning]);
    });

    test('information waits for a hazard to finish', () async {
      unawaited(queue.announce('Stop. car right in front of you',
          priority: SpeechPriority.hazard));
      await settle();
      unawaited(queue.speak('Guidance ready.'));
      await settle();

      expect(engine.cutOff, isEmpty);
      expect(engine.speaking, 'Stop. car right in front of you');
      expect(queue.pending, ['Guidance ready.']);
    });

    test('navigation waits for a hazard to finish', () async {
      unawaited(queue.announce('Stop. car right in front of you',
          priority: SpeechPriority.hazard));
      await settle();
      unawaited(
          queue.announce('Turn left.', priority: SpeechPriority.navigation));
      await settle();

      expect(engine.cutOff, isEmpty);
      engine.complete();
      await settle();
      expect(engine.started.last, 'Turn left.');
    });
  });

  group('clearing narration', () {
    test('drops information, never a hazard or a direction', () async {
      // What leaving a screen and opening the microphone both do. stop() used
      // to be called instead, and it dropped the hazard too. Directions went
      // with the information, so the map screen's opening words dropped the
      // turns queued behind them.
      unawaited(queue.announce('Stop. car on your left',
          priority: SpeechPriority.hazard));
      await settle();
      unawaited(queue.announce('In fifty metres, turn right.',
          priority: SpeechPriority.navigation));
      unawaited(queue.announce('Path looks clear',
          priority: SpeechPriority.info));
      await settle();

      queue.clearNarration();
      await settle();

      expect(engine.cutOff, isEmpty, reason: 'the hazard being said goes on');
      expect(engine.speaking, 'Stop. car on your left');
      expect(queue.pending, ['In fifty metres, turn right.']);
    });

    test('a prompt does not drop the turn waiting behind it', () async {
      unawaited(queue.speak('Guidance ready. Heading for Home.'));
      await settle();
      unawaited(queue.announce('Now, turn left.',
          priority: SpeechPriority.navigation));
      unawaited(queue.speak('Say scan, or help.'));
      await settle();
      expect([engine.speaking, ...queue.pending], contains('Now, turn left.'));
      expect(engine.cutOff, isNot(contains('Now, turn left.')));
    });

    test('cuts off narration in progress', () async {
      unawaited(queue.speak('Reading text. Hold the phone above the page.'));
      await settle();
      queue.clearNarration();
      await settle();
      expect(engine.cutOff, ['Reading text. Hold the phone above the page.']);
    });
  });

  group('what may interrupt what', () {
    test('a hazard cuts off information', () async {
      unawaited(queue.speak('Path looks clear'));
      await settle();
      unawaited(queue.announce('Stop. chair right in front of you',
          priority: SpeechPriority.hazard));
      await settle();

      expect(engine.cutOff, ['Path looks clear']);
      expect(engine.speaking, 'Stop. chair right in front of you');
    });

    test('a hazard cuts off navigation', () async {
      unawaited(queue.announce('In fifty metres, turn right.',
          priority: SpeechPriority.navigation));
      await settle();
      unawaited(queue.announce('Stop. chair right in front of you',
          priority: SpeechPriority.hazard));
      await settle();

      expect(engine.cutOff, ['In fifty metres, turn right.']);
    });

    test('a different hazard cuts off the current one', () async {
      // A new danger is new information; the old sentence is stale.
      unawaited(queue.announce('Stop. chair right in front of you',
          priority: SpeechPriority.hazard));
      await settle();
      unawaited(queue.announce('Stop. car right in front of you',
          priority: SpeechPriority.hazard));
      await settle();

      expect(engine.cutOff, ['Stop. chair right in front of you']);
      expect(engine.speaking, 'Stop. car right in front of you');
    });

    test('navigation never cuts off information mid-sentence', () async {
      unawaited(queue.speak('Guidance ready. Hold the phone up.'));
      await settle();
      unawaited(
          queue.announce('Turn left.', priority: SpeechPriority.navigation));
      await settle();

      expect(engine.cutOff, isEmpty);
      expect(queue.pending, ['Turn left.']);
    });

    test('navigation goes ahead of queued information', () async {
      unawaited(queue.speak('One.'));
      await settle();
      unawaited(queue.announce('Two.', priority: SpeechPriority.info));
      unawaited(
          queue.announce('Turn left.', priority: SpeechPriority.navigation));
      await settle();

      expect(queue.pending, ['Turn left.', 'Two.']);
    });
  });

  group('screens talking', () {
    test('speak replaces pending narration, as it always did', () async {
      // A user who pressed a button does not want the rest of the previous
      // screen first.
      unawaited(queue.speakLines(['Title', 'Body one', 'Body two']));
      await settle();
      unawaited(queue.speak('Enter the name of the person to call.'));
      await settle();

      expect(engine.cutOff, ['Title']);
      expect(queue.pending, isEmpty);
      expect(engine.speaking, 'Enter the name of the person to call.');
    });

    test('speak does not cut off a hazard, but does replace what was waiting',
        () async {
      unawaited(queue.announce('Stop. car right in front of you',
          priority: SpeechPriority.hazard));
      await settle();
      unawaited(queue.speak('Old narration'));
      unawaited(queue.speak('New narration'));
      await settle();

      expect(engine.cutOff, isEmpty);
      expect(queue.pending, ['New narration']);
    });

    test('lines are said in order, each to the end', () async {
      final done = queue.speakLines(['A', 'B', 'C']);
      await settle();
      expect(engine.speaking, 'A');
      engine.complete();
      await settle();
      expect(engine.speaking, 'B');
      engine.complete();
      await settle();
      expect(engine.speaking, 'C');
      engine.complete();
      await done;
      expect(engine.finished, ['A', 'B', 'C']);
      expect(engine.cutOff, isEmpty);
    });

    test('stop clears everything', () async {
      unawaited(queue.speakLines(['A', 'B', 'C']));
      await settle();
      await queue.stop();
      expect(engine.cutOff, ['A']);
      expect(queue.pending, isEmpty);
      expect(queue.current, isNull);
    });

    test('a request that was dropped still completes its future', () async {
      // SosEngine awaits the alarm sentence. If a dropped request never
      // completed, an SOS could hang forever behind a sentence nobody said.
      final dropped = queue.speak('Old');
      final replaced = queue.speak('New');
      await settle();
      await queue.stop();
      await dropped.timeout(const Duration(seconds: 1));
      await replaced.timeout(const Duration(seconds: 1));
    });

    test('repeat says the last thing again, or that there is nothing', () async {
      unawaited(queue.repeat());
      await settle();
      expect(engine.speaking, kNothingToRepeat);
      engine.complete();
      await settle();

      unawaited(queue.speak('Path looks clear'));
      await settle();
      engine.complete();
      await settle();
      unawaited(queue.repeat());
      await settle();
      expect(engine.speaking, 'Path looks clear');
      expect(queue.lastSpoken, 'Path looks clear');
    });

    test('an engine that throws does not take the queue down', () async {
      final broken = _ThrowingEngine();
      final q = SpeechQueue(engine: broken);
      await q.speak('one');
      await q.announce('Stop.', priority: SpeechPriority.hazard);
      expect(broken.attempts, ['one', 'Stop.']);
    });
  });
}

class _ThrowingEngine implements SpeechEngine {
  final List<String> attempts = [];

  @override
  Future<void> say(String text) async {
    attempts.add(text);
    throw StateError('no voice installed');
  }

  @override
  Future<void> stop() async {}
}
