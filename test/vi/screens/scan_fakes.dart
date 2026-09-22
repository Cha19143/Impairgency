import 'package:flutter/material.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/navigation/map_services.dart';
import 'package:impairgency/core/navigation/route.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/vision/depth.dart';
import 'package:impairgency/core/vision/detection.dart';
import 'package:impairgency/data/scan_service.dart';

class RecordingSpeaker implements PrioritySpeaker {
  final List<(String, SpeechPriority?)> said = [];
  @override
  String? get lastSpoken => said.isEmpty ? null : said.last.$1;
  @override
  Future<void> repeat() async {}
  @override
  Future<void> speak(String text) async => said.add((text, null));
  @override
  Future<void> speakLines(List<String> lines) async =>
      said.addAll(lines.map((l) => (l, null)));
  @override
  Future<void> announce(String text, {required SpeechPriority priority}) async =>
      said.add((text, priority));
  @override
  Future<void> stop() async {}
}

/// A scan service with no camera and no model: the test drives detections.
class FakeScan extends ScanService {
  void Function(ScanFrame)? onFrame;

  /// One frame from the camera: these objects, and this floor.
  void see(List<Detection> detections,
          {DepthReading depth = DepthReading.none, String? notice}) =>
      onFrame!(ScanFrame(
          detections: detections, depth: depth, notice: notice));
  int starts = 0;
  @override
  Future<bool> loadModel() async => true;
  @override
  Future<bool> start(void Function(ScanFrame) onFrame) async {
    starts++;
    this.onFrame = onFrame;
    return true;
  }

  @override
  Future<void> dispose() async {}
}

const home = Destination(
    id: 'home', label: 'Home', latitude: 14.79, longitude: 120.92,
    kind: DestinationKind.home);
const clinic = Destination(id: 'p1', label: 'Clinic', latitude: 14.8, longitude: 120.93);

Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

class FakeRouting implements RoutingService {
  FakeRouting(this.answer);
  final Future<WalkingRoute> Function(RoutePoint from, RoutePoint to) answer;
  @override
  Future<WalkingRoute> walkingRoute(RoutePoint from, RoutePoint to) =>
      answer(from, to);
}
