/// The fall, as one moment a later clip can hook, and as the history row.
///
/// [keepImportantFall] is the function to call. The sensor does not write
/// anything itself.
library;

import '../location/location_fix.dart';
import '../places/session_event.dart';
import '../voice/voice_commands.dart';

/// Document field `type` on `location_history/{uid}/events`.
const String kFallDetectedType = 'fall_detected';

/// What the check-in heard.
enum FallReply { okay, help, none, abandoned }

/// Yes, "I'm okay", and help. Nothing else in this window is an answer.
const Set<VoiceCommand> kFallReplyCommands = {
  VoiceCommand.yes,
  VoiceCommand.allClear,
  VoiceCommand.help,
};

FallReply fallReplyFrom(VoiceCommand? command) => switch (command) {
  VoiceCommand.help => FallReply.help,
  VoiceCommand.yes || VoiceCommand.allClear => FallReply.okay,
  _ => FallReply.none,
};

/// The moment the pattern tripped. [answered] is filled in when the
/// check-in ends.
class FallMoment {
  FallMoment({required this.at});

  final DateTime at;
  bool answered = false;
  LocationFix? position;
}

/// Step E should hook this, not the accelerometer.
FallMoment keepImportantFall({required DateTime at}) => FallMoment(at: at);

/// Where a finished fall is written. Tests record instead of opening Firestore.
abstract interface class FallHistorySink {
  Future<void> record(
    String uid,
    FallMoment moment, {
    required String sessionId,
  });
}

/// Fields for the history row. The repository adds the Firestore `at`.
Map<String, Object?> fallEventFields(
  FallMoment moment, {
  required String sessionId,
}) => {
  'type': kFallDetectedType,
  'kind': SessionEventKind.fallDetected.name,
  'sessionId': sessionId,
  'answered': moment.answered,
  'detail': moment.answered ? 'answered' : 'no response',
  if (moment.position != null) 'lat': moment.position!.latitude,
  if (moment.position != null) 'lng': moment.position!.longitude,
};
