/// What the app noticed, told to the guardian.
///
/// The tester's dashboard mock shows "Obstacle detected: chair, 2 mins ago"
/// and "Text read: medicine bottle, 15 mins ago". These are the rows behind
/// it. They are written by the user's phone, only while the user has said
/// "Share what the app notices", and they are the *headline* of each thing
/// - the object's name, the first line of a page - never the camera frame.
library;

import '../location/location_policy.dart' show describeAge;

enum ActivityKind { obstacle, textRead, journey }

class ActivityEvent {
  const ActivityEvent({
    required this.kind,
    required this.detail,
    required this.at,
  });

  final ActivityKind kind;

  /// The object, the first line, the destination. Short by construction:
  /// see [headline].
  final String detail;
  final DateTime at;

  /// The most characters of a detail that are worth sending. A page's first
  /// line says what the page is; a page's whole text is the user's business.
  static const int maxDetailLength = 60;

  /// Trims [raw] to one line of at most [maxDetailLength] characters.
  static String headline(String raw) {
    final line = raw.trim().split(RegExp(r'[\r\n]+')).first.trim();
    if (line.length <= maxDetailLength) return line;
    return '${line.substring(0, maxDetailLength - 1).trimRight()}…';
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'detail': detail,
      };

  static ActivityEvent? fromJson(Map<String, Object?> data, DateTime at) {
    final kind = ActivityKind.values.cast<ActivityKind?>().firstWhere(
          (k) => k!.name == data['kind'],
          orElse: () => null,
        );
    final detail = data['detail'];
    if (kind == null || detail is! String) return null;
    return ActivityEvent(kind: kind, detail: detail, at: at);
  }
}

/// "Obstacle: chair", "Read: MEDICINE - take one daily", "Set off for Work".
String activityHeadline(ActivityEvent event) => switch (event.kind) {
      ActivityKind.obstacle => 'Obstacle: ${event.detail}',
      ActivityKind.textRead => 'Read: ${event.detail}',
      ActivityKind.journey => 'Set off for ${event.detail}',
    };

/// The headline and its age, for a card and for a screen reader.
String describeActivity(ActivityEvent event, {required DateTime now}) =>
    '${activityHeadline(event)}, ${describeAge(now.difference(event.at))}';

/// Keeps the feed to things worth a row.
///
/// The scan screen warns about a chair several times a minute while the
/// user walks past it. One row per object per minute is the guardian's view
/// of that; more is noise that buries the stairs.
class ActivityThrottle {
  ActivityThrottle({this.window = const Duration(minutes: 1)});

  final Duration window;
  final _last = <String, DateTime>{};

  /// Whether to record [detail] of [kind] at [now], and remembers it if so.
  bool admit(ActivityKind kind, String detail, DateTime now) {
    final key = '${kind.name}:${detail.toLowerCase()}';
    final last = _last[key];
    if (last != null && now.difference(last) < window) return false;
    _last[key] = now;
    return true;
  }
}
