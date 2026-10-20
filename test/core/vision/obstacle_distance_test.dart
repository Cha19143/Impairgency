import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/vision/depth.dart';
import 'package:impairgency/core/vision/detection.dart';
import 'package:impairgency/core/vision/obstacle_distance.dart';

void main() {
  test('a box at the stop size is about a metre and a half', () {
    expect(estimateDistanceFromExtent(0.55), closeTo(1.55, 0.02));
    expect(estimateDistanceFromExtent(0.25), closeTo(3.4, 0.01));
    expect(estimateDistanceFromExtent(2), 0.5);
    expect(estimateDistanceFromExtent(0.01), 15);
  });

  test('depth nearness at a stop is about a metre and a half', () {
    expect(estimateDistanceFromNearness(0.8), closeTo(1.5, 0.01));
  });

  test('an urgent warning keeps an approximate distance from the box', () {
    final car = Detection(
      label: 'car',
      score: 0.9,
      centerX: 0.5,
      extent: 0.6,
    );
    final guidance = guidanceFor([car]);
    expect(guidance.urgent, isTrue);
    final notice = urgentObstacleNotice(
      guidance: guidance,
      detections: [car],
      depth: DepthReading.none,
    );
    expect(notice, isNotNull);
    expect(notice!.type, 'car');
    expect(notice.distanceApproximate, isTrue);
    expect(notice.distanceMetres, closeTo(0.85 / 0.6, 0.01));
  });

  test('a warning that is not urgent is not a history row', () {
    final chair = Detection(
      label: 'chair',
      score: 0.9,
      centerX: 0.5,
      extent: 0.2,
    );
    final guidance = guidanceFor([chair]);
    expect(guidance.urgent, isFalse);
    expect(
      urgentObstacleNotice(
        guidance: guidance,
        detections: [chair],
        depth: DepthReading.none,
      ),
      isNull,
    );
  });

  test('an unnamed blockage uses the depth cue, still approximate', () {
    final notice = urgentObstacleNotice(
      guidance: const Guidance(
        phrase: 'Stop. Something right in front of you.',
        urgent: true,
        label: 'obstacle',
      ),
      detections: const [],
      depth: const DepthReading(
        nearness: 0.8,
        direction: DepthDirection.ahead,
        confidence: 0.9,
      ),
    );
    expect(notice!.type, 'obstacle');
    expect(notice.distanceApproximate, isTrue);
    expect(notice.distanceMetres, closeTo(1.5, 0.01));
  });
}
