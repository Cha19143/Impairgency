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
    this.goTo,
    this.rememberFriend,
    this.forgetFriend,
  });

  final LocationSource location;

  /// Usually `bestEffortFix`. Injected so a test can decide what came back.
  final Future<({LocationAvailability availability, String? summary})>
      Function() fetchFix;

  final String? contactName;
  final bool hasGuardian;
  final bool hasDevice;

  /// "Take me to…": finds the place and starts directions. Null in tests that
  /// do not need it, and the answer then says how to choose a place instead.
  final Future<VoiceOutcome> Function(String place)? goTo;

  /// "Hello friend Sam", heard away from the scan screen: opens it to take
  /// Sam's face down. Null in tests that do not need it.
  final Future<VoiceOutcome> Function(String name)? rememberFriend;

  /// "Forget Sam": asks, then deletes Sam's saved face.
  final Future<VoiceOutcome> Function(String name)? forgetFriend;

  /// What [command] does. [argument] is the place or name that came with it.
  Future<VoiceOutcome> handle(VoiceCommand command, {String? argument}) async =>
      switch (command) {
        // These went to the dashboard, where the user usually already was, so
        // "Opening scan." was said and nothing opened.
        VoiceCommand.scan => const VoiceOutcome(
            spoken: 'Opening scan.', route: Routes.scan),
        VoiceCommand.navigate => const VoiceOutcome(
            spoken: 'Opening smart assistance.', route: Routes.assist),
        VoiceCommand.help => const VoiceOutcome(
            spoken: 'Calling for help.', route: Routes.sos),
        VoiceCommand.whereAmI => _whereAmI(),
        VoiceCommand.callGuardian => _callGuardian(),
        VoiceCommand.connectDevice => _connectDevice(),
        VoiceCommand.cancel =>
          const VoiceOutcome(spoken: 'There is nothing to cancel.'),
        VoiceCommand.repeat => const VoiceOutcome(
            spoken: kNothingToRepeat, repeatLast: true),
        VoiceCommand.navigateTo => _goTo(argument),
        VoiceCommand.read => const VoiceOutcome(
            spoken: 'Opening read text.', route: Routes.readText),
        VoiceCommand.back => const VoiceOutcome(
            spoken: 'Going to the main screen.', route: Routes.home),
        VoiceCommand.whatCanISay => const VoiceOutcome(
            spoken: 'Here is what you can say.', route: Routes.whatCanISay),
        // The rest belong to one screen. Heard anywhere else, the answer says
        // where they work rather than "not a command", which would be untrue.
        VoiceCommand.next || VoiceCommand.pause || VoiceCommand.resume =>
          const VoiceOutcome(
              spoken: 'That works while a page is being read. Say read to '
                  'open read text.'),
        VoiceCommand.stopDirections => const VoiceOutcome(
            spoken: 'There are no directions to stop.'),
        VoiceCommand.savePlace => const VoiceOutcome(
            spoken: 'Places are saved from Smart assistance, while you are '
                'standing in them.'),
        VoiceCommand.rememberFriend when rememberFriend != null =>
          _withName(argument, rememberFriend!,
              'Say hello friend, and then their name.'),
        VoiceCommand.forgetFriend when forgetFriend != null =>
          _withName(argument, forgetFriend!, 'Say forget, and then their name.'),
        VoiceCommand.rememberFriend ||
        VoiceCommand.forgetFriend ||
        VoiceCommand.whoIsHere =>
          const VoiceOutcome(
              spoken: 'People are recognised on the scan screen. Say scan to '
                  'open it.'),
        VoiceCommand.yes || VoiceCommand.no => const VoiceOutcome(
            spoken: 'There is no question waiting for an answer.'),
      };

  Future<VoiceOutcome> _withName(String? name,
      Future<VoiceOutcome> Function(String name) handler, String ask) async {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return VoiceOutcome(spoken: ask);
    return handler(trimmed);
  }

  Future<VoiceOutcome> _goTo(String? place) async {
    final name = place?.trim() ?? '';
    if (name.isEmpty) {
      return const VoiceOutcome(
          spoken: 'Say where to, for example: take me home.');
    }
    final go = goTo;
    if (go == null) {
      return const VoiceOutcome(
          spoken: 'Opening smart assistance, to choose where you are going.',
          route: Routes.assist);
    }
    return go(name);
  }

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
  /// who asked for their guardian and got somebody else would not know. The
  /// app cannot phone a guardian - it has no number it may read - so with a
  /// guardian this opens the emergency alert, and says exactly what that does:
  /// it used to say "Calling your guardian." and then ring the contact.
  VoiceOutcome _callGuardian() {
    if (hasGuardian) {
      final call = contactName == null ? '' : ', and calls $contactName';
      return VoiceOutcome(
        spoken: 'The app cannot phone your guardian directly. Starting an '
            'emergency alert instead: it alerts your guardian$call. Say '
            'cancel to stop it.',
        route: Routes.sos,
      );
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
