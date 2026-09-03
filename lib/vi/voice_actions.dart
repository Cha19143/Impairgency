import '../app/routes.dart';
import '../core/location/location_policy.dart';
import '../core/location/location_source.dart';
import '../core/speech/speaker.dart';
import '../core/voice/voice_commands.dart';

/// What a spoken command does: something to say, and somewhere to go.
class VoiceOutcome {
  const VoiceOutcome({required this.spoken, this.route, this.repeatLast = false});

  final String spoken;

  /// Where to navigate, or null to stay put.
  final String? route;

  /// Say the previous utterance again rather than [spoken].
  ///
  /// A flag rather than an empty [spoken], because "say nothing new" and "say
  /// the empty string" are different things and a test caught me conflating
  /// them. Only the speaker knows what was said last.
  final bool repeatLast;
}

/// Handlers for the six functions §2.C names.
///
/// `cprwire` implemented three of them: scan, navigate, help. The other three
/// were advertised by the microphone icon on ten screens and did nothing.
///
/// Takes its dependencies, so every answer can be asserted without a
/// microphone, a satellite or a phone line.
class VoiceActions {
  const VoiceActions({
    required this.location,
    required this.fetchFix,
    this.contactName,
    this.hasGuardian = false,
    this.hasDevice = false,
  });

  final LocationSource location;

  /// Usually `bestEffortFix`. Injected so a test can decide what came back.
  final Future<({LocationAvailability availability, String? summary})>
      Function() fetchFix;

  final String? contactName;
  final bool hasGuardian;
  final bool hasDevice;

  Future<VoiceOutcome> handle(VoiceCommand command) async =>
      switch (command) {
        VoiceCommand.scan => const VoiceOutcome(
            spoken: 'Opening scan.', route: Routes.home),
        VoiceCommand.navigate => const VoiceOutcome(
            spoken: 'Opening guidance.', route: Routes.home),
        VoiceCommand.help => const VoiceOutcome(
            spoken: 'Calling for help.', route: Routes.sos),
        VoiceCommand.whereAmI => _whereAmI(),
        VoiceCommand.callGuardian => _callGuardian(),
        VoiceCommand.connectDevice => _connectDevice(),
        VoiceCommand.cancel =>
          const VoiceOutcome(spoken: 'There is nothing to cancel.'),
        VoiceCommand.repeat => const VoiceOutcome(
            spoken: kNothingToRepeat, repeatLast: true),
      };

  /// §2.C, "checking the user's location".
  ///
  /// Says the *quality* of the answer, not just an answer. A position accurate
  /// to two kilometres read out as a location is worse than saying it is a
  /// rough guess.
  Future<VoiceOutcome> _whereAmI() async {
    final result = await fetchFix();
    if (result.summary != null) {
      return VoiceOutcome(spoken: result.summary!);
    }
    return VoiceOutcome(spoken: permissionGuidance(result.availability));
  }

  /// §2.C, "contacting a guardian".
  ///
  /// Deliberately does not silently fall back to the emergency contact: a user
  /// who asked for their guardian and got somebody else would not know.
  VoiceOutcome _callGuardian() {
    if (hasGuardian) {
      return const VoiceOutcome(
          spoken: 'Calling your guardian.', route: Routes.sos);
    }
    if (contactName != null) {
      return VoiceOutcome(
        spoken: 'You have no guardian yet. Your emergency contact is '
            '$contactName. Say help to call them.',
      );
    }
    return const VoiceOutcome(
      spoken: 'You have no guardian and no emergency contact yet. You can add '
          'them in settings.',
    );
  }

  /// §2.C, "connecting to supported devices" — and honest that §5 is out of
  /// scope, rather than pretending to search for hardware that does not exist.
  VoiceOutcome _connectDevice() {
    if (hasDevice) {
      return const VoiceOutcome(
        spoken: 'Device support is not built yet. Everything works on the '
            'phone by itself.',
        route: Routes.settings,
      );
    }
    return const VoiceOutcome(
      spoken: 'There is no device to connect. Scanning, guidance and emergency '
          'SOS all work on the phone by itself.',
    );
  }
}
