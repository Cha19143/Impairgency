/// A short strip of gray frames around one important moment.
///
/// Not a recording of the walk. The phone keeps a few seconds, and writes
/// them once, when the moment has gone quiet. [kClipsEnabled] turns the
/// whole of that off. Detection does not read it.
library;

import 'dart:typed_data';

import '../vision/yuv_frame.dart';

/// Master switch. False skips the frame grab, the buffer, and the write.
///
/// Detection, speech, and the five triggers keep working. This is the one
/// place to turn clips off.
const bool kClipsEnabled = true;

/// How much of the walk before the trigger is kept.
const Duration kClipBuffer = Duration(seconds: 8);

/// How long to keep recording after a trigger, restarted when another
/// trigger arrives while this one is still open.
const Duration kClipTail = Duration(seconds: 3);

/// How long after the first trigger the tail may be pushed out to.
///
/// A run of triggers cannot film for longer than the buffer plus this.
const Duration kClipMaxAfter = Duration(seconds: 10);

/// How long after one clip starts before another may start.
///
/// Merging into a clip that is still open is not a new clip. SOS does not
/// wait, and does not make the next clip wait.
const Duration kClipMinGap = Duration(seconds: 60);

/// How many clips one user may start in an hour. SOS is not counted.
const int kClipHourlyCap = 20;

const Duration kClipHour = Duration(hours: 1);

/// How long a saved clip stays. The phone deletes its own after this.
/// [expiresAt] is written as well, for a console TTL later. Nothing here
/// depends on that TTL existing.
const Duration kClipRetention = Duration(days: 7);

/// The saved picture. Small on purpose: it is a reminder of the moment,
/// and it has to fit in one Firestore document.
const int kClipWidth = 160;
const int kClipHeight = 120;

/// Same pace as detection, so the strip and the warnings describe one walk.
const Duration kClipFrameGap = Duration(milliseconds: 350);

const int kClipJpegQuality = 40;

const String kClipTriggerObstacle = 'obstacle';
const String kClipTriggerFall = 'fall';
const String kClipTriggerSos = 'sos';
const String kClipTriggerStationary = 'stationary_1h';
const String kClipTriggerDeviation = 'route_deviation';

/// What the admin filter offers, in the order it offers them.
const List<String> kClipTriggerOrder = [
  kClipTriggerObstacle,
  kClipTriggerFall,
  kClipTriggerSos,
  kClipTriggerStationary,
  kClipTriggerDeviation,
];

/// Shown when a clip was saved with the camera off. SOS and an hour of
/// standing still often have no pictures, and the page says so.
const String kClipNoFramesMessage =
    'No camera was on, so this event has no pictures.';

String clipTriggerLabel(String trigger) => switch (trigger) {
      kClipTriggerObstacle => 'Obstacle',
      kClipTriggerFall => 'Fall',
      kClipTriggerSos => 'SOS',
      kClipTriggerStationary => 'Stationary 1 hour',
      kClipTriggerDeviation => 'Route deviation',
      _ => trigger,
    };

/// One gray picture, still uncompressed. JPEG happens when the clip closes,
/// off the camera path.
class GrayFrame {
  GrayFrame({
    required this.at,
    required this.width,
    required this.height,
    required this.pixels,
  });

  final DateTime at;
  final int width;
  final int height;

  /// Row-major, one byte per pixel, 0 to 255. Length is [width] * [height].
  final Uint8List pixels;
}

/// The Y plane, sampled down to [width] by [height], already the right way up.
///
/// [YuvFrame.lumaAt] does the rotation. This only picks every nth pixel, so
/// the copy inside the camera callback stays a tight loop.
Uint8List subsampleGray(
  YuvFrame frame, {
  int width = kClipWidth,
  int height = kClipHeight,
}) {
  final out = Uint8List(width * height);
  final sourceWidth = frame.uprightWidth;
  final sourceHeight = frame.uprightHeight;
  if (sourceWidth <= 0 || sourceHeight <= 0 || width <= 0 || height <= 0) {
    return out;
  }
  for (var y = 0; y < height; y++) {
    final sy = (y + 0.5) * sourceHeight / height;
    final row = y * width;
    for (var x = 0; x < width; x++) {
      final sx = (x + 0.5) * sourceWidth / width;
      out[row + x] = frame.lumaAt(sx, sy);
    }
  }
  return out;
}

/// A clip the buffer has finished, ready to be written once.
class ClosedClip {
  ClosedClip({
    required this.triggers,
    required this.at,
    required this.endedAt,
    this.latitude,
    this.longitude,
    required this.frames,
  });

  final List<String> triggers;

  /// When the first trigger fired, not when the buffer starts.
  final DateTime at;
  final DateTime endedAt;
  double? latitude;
  double? longitude;
  final List<GrayFrame> frames;
}

/// One clip as the admin page lists it. The pictures are loaded separately.
class EventClipRecord {
  const EventClipRecord({
    required this.id,
    required this.userId,
    required this.triggers,
    required this.at,
    required this.endedAt,
    this.latitude,
    this.longitude,
    required this.frameCount,
    required this.hasFrames,
  });

  final String id;
  final String userId;
  final List<String> triggers;
  final DateTime at;
  final DateTime endedAt;
  final double? latitude;
  final double? longitude;
  final int frameCount;
  final bool hasFrames;
}

/// One JPEG the player shows.
class StoredClipFrame {
  const StoredClipFrame({
    required this.index,
    required this.jpeg,
    required this.width,
    required this.height,
  });

  final int index;
  final Uint8List jpeg;
  final int width;
  final int height;
}

class _OpenClip {
  _OpenClip({
    required this.triggers,
    required this.at,
    required this.deadline,
    required this.maxEnd,
    this.latitude,
    this.longitude,
    required this.frames,
  });

  final List<String> triggers;
  final DateTime at;
  DateTime deadline;
  final DateTime maxEnd;
  double? latitude;
  double? longitude;
  final List<GrayFrame> frames;

  ClosedClip close() => ClosedClip(
        triggers: List<String>.unmodifiable(triggers),
        at: at,
        endedAt: deadline,
        latitude: latitude,
        longitude: longitude,
        frames: frames,
      );
}

/// The rolling buffer and the one clip that may be open.
///
/// [enabled] defaults to [kClipsEnabled]. Tests pass false. The app does not.
class ClipAssembler {
  ClipAssembler({bool? enabled}) : enabled = enabled ?? kClipsEnabled;

  final bool enabled;

  final List<GrayFrame> _buffer = [];
  _OpenClip? _open;
  ClosedClip? _pending;
  DateTime? _lastStarted;
  final List<DateTime> _started = [];

  /// When the open clip should be written. Null when nothing is open.
  DateTime? get deadline => _open?.deadline;

  void clear() {
    _buffer.clear();
    _open = null;
    _pending = null;
  }

  void addFrame(GrayFrame frame) {
    if (!enabled) return;
    _buffer.add(frame);
    final cutoff = frame.at.subtract(kClipBuffer);
    while (_buffer.isNotEmpty && _buffer.first.at.isBefore(cutoff)) {
      _buffer.removeAt(0);
    }
    final open = _open;
    if (open != null && !frame.at.isAfter(open.deadline)) {
      open.frames.add(frame);
    }
  }

  /// Starts a clip, or folds [trigger] into the one already open.
  ///
  /// False when the gap or the hourly cap refused a new clip. SOS is never
  /// refused. A trigger during the tail is a merge, not a new clip, so the
  /// gap does not apply to it.
  bool note(
    String trigger,
    DateTime now, {
    double? latitude,
    double? longitude,
  }) {
    if (!enabled) return false;
    _seal(now);
    final open = _open;
    if (open != null && !now.isAfter(open.deadline)) {
      if (!open.triggers.contains(trigger)) open.triggers.add(trigger);
      final next = now.add(kClipTail);
      open.deadline = next.isBefore(open.maxEnd) ? next : open.maxEnd;
      if (open.latitude == null && latitude != null) {
        open.latitude = latitude;
        open.longitude = longitude;
      }
      return true;
    }
    if (!_admit(trigger, now)) return false;
    final start = now.subtract(kClipBuffer);
    _open = _OpenClip(
      triggers: [trigger],
      at: now,
      deadline: now.add(kClipTail),
      maxEnd: now.add(kClipMaxAfter),
      latitude: latitude,
      longitude: longitude,
      frames: [
        for (final frame in _buffer)
          if (!frame.at.isBefore(start)) frame,
      ],
    );
    if (trigger != kClipTriggerSos) {
      _lastStarted = now;
      _started.add(now);
    }
    return true;
  }

  /// A position that arrived after the trigger. Kept if the clip is still
  /// here, including one that has closed but not been saved yet.
  void attachPosition(double latitude, double longitude) {
    final open = _open;
    if (open != null && open.latitude == null) {
      open.latitude = latitude;
      open.longitude = longitude;
      return;
    }
    final pending = _pending;
    if (pending != null && pending.latitude == null) {
      pending.latitude = latitude;
      pending.longitude = longitude;
    }
  }

  /// The clip, once its tail has elapsed. Null while it is still open.
  ClosedClip? takeDue(DateTime now) {
    _seal(now);
    final pending = _pending;
    _pending = null;
    return pending;
  }

  void _seal(DateTime now) {
    final open = _open;
    if (open == null || now.isBefore(open.deadline)) return;
    _open = null;
    _pending = open.close();
  }

  bool _admit(String trigger, DateTime now) {
    if (trigger == kClipTriggerSos) return true;
    final last = _lastStarted;
    if (last != null && now.difference(last) < kClipMinGap) return false;
    _started.removeWhere((t) => now.difference(t) >= kClipHour);
    return _started.length < kClipHourlyCap;
  }
}
