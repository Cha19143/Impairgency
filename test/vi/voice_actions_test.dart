import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/core/voice/voice_commands.dart';
import 'package:impairgency/vi/voice_actions.dart';

class _Source implements LocationSource {
  const _Source(this.state);
  final LocationAvailability state;

  @override
  Future<LocationAvailability> availability() async => state;
  @override
  Future<LocationAvailability> requestPermission() async => state;
  @override
  Future<LocationFix?> currentFix({Duration timeout = Duration.zero}) async =>
      null;
  @override
  Future<LocationFix?> lastKnownFix() async => null;
}

VoiceActions actions({
  LocationAvailability availability = LocationAvailability.ready,
  String? summary,
  String? contactName,
  bool hasGuardian = false,
  bool hasDevice = false,
}) =>
    VoiceActions(
      location: _Source(availability),
      fetchFix: () async => (availability: availability, summary: summary),
      contactName: contactName,
      hasGuardian: hasGuardian,
      hasDevice: hasDevice,
    );

void main() {
  group('all six §2.C functions answer', () {
    test('every command produces something to say', () async {
      for (final command in VoiceCommand.values) {
        final outcome = await actions(summary: 'Your location was sent.')
            .handle(command);
        // "Stop" means stop talking: saying something would not be stopping.
        if (outcome.stopSpeaking) continue;
        expect(outcome.spoken.trim(), isNotEmpty, reason: '$command');
      }
    });

    test('repeat asks the speaker rather than inventing something to say',
        () async {
      // Only the speaker knows what was said last, so the outcome says "repeat
      // the last thing" rather than carrying text of its own.
      final outcome = await actions().handle(VoiceCommand.repeat);
      expect(outcome.repeatLast, isTrue);
      expect(outcome.route, isNull);
      // The fallback is what gets said when there is nothing to repeat.
      expect(outcome.spoken, contains('nothing to repeat'));
    });

    test('no other command asks for a repeat', () async {
      for (final command in VoiceCommand.values) {
        if (command == VoiceCommand.repeat) continue;
        final outcome = await actions(summary: 'x').handle(command);
        expect(outcome.repeatLast, isFalse, reason: '$command');
      }
    });

    test('help goes straight to the SOS flow', () async {
      final outcome = await actions().handle(VoiceCommand.help);
      expect(outcome.route, Routes.sos);
    });

    test('scan and navigate open their screens, not the dashboard', () async {
      // The tester's "Tap to speak does nothing": both went to /home, where
      // the user already was, so "Opening scan." was said and nothing opened.
      expect((await actions().handle(VoiceCommand.scan)).route, Routes.scan);
      expect((await actions().handle(VoiceCommand.navigate)).route,
          Routes.assist);
    });
  });

  group('where am I (#46)', () {
    test('reads back the location policy sentence, quality included', () async {
      const prose = 'Your last known location, from 20 minutes ago, was sent.';
      final outcome =
          await actions(summary: prose).handle(VoiceCommand.whereAmI);
      expect(outcome.spoken, prose);
    });

    test('explains a refusal rather than saying nothing', () async {
      final outcome = await actions(
        availability: LocationAvailability.deniedForever,
        summary: null,
      ).handle(VoiceCommand.whereAmI);

      expect(outcome.spoken, contains('Settings'));
    });

    test('each permission state gets its own answer', () async {
      final said = <String>{};
      for (final state in LocationAvailability.values) {
        final outcome =
            await actions(availability: state).handle(VoiceCommand.whereAmI);
        said.add(outcome.spoken);
      }
      expect(said.length, LocationAvailability.values.length);
    });
  });

  group('call my guardian (#47)', () {
    test('with a guardian, starts the emergency alert and says what it does',
        () async {
      // It used to say "Calling your guardian." and then ring the emergency
      // contact, which is not the guardian and was never said.
      final outcome = await actions(hasGuardian: true, contactName: 'Mum')
          .handle(VoiceCommand.callGuardian);
      expect(outcome.spoken, isNot(contains('Calling your guardian')));
      expect(outcome.spoken, contains('cannot phone your guardian'));
      expect(outcome.spoken, contains('calls Mum'));
      expect(outcome.spoken, contains('Say cancel'));
      expect(outcome.route, Routes.sos);
    });

    test('never quietly rings someone else instead', () async {
      // A user who asked for their guardian and got the emergency contact
      // would have no way to know.
      final outcome = await actions(contactName: 'Mum')
          .handle(VoiceCommand.callGuardian);

      expect(outcome.route, isNull, reason: 'nothing is dialled');
      expect(outcome.spoken, contains('no guardian'));
      expect(outcome.spoken, contains('Mum'));
      expect(outcome.spoken, contains('Say help'));
    });

    test('says what to do when there is nobody at all', () async {
      final outcome = await actions().handle(VoiceCommand.callGuardian);
      expect(outcome.spoken, contains('no guardian and no emergency contact'));
      expect(outcome.spoken, contains('settings'));
    });
  });

  group('connect my device (#48)', () {
    test('is honest that hardware support is out of scope', () async {
      final outcome = await actions().handle(VoiceCommand.connectDevice);
      expect(outcome.spoken, contains('no device to connect'));
      expect(outcome.spoken, contains('phone by itself'));
    });

    test('does not pretend to search for hardware that does not exist',
        () async {
      final outcome =
          await actions(hasDevice: true).handle(VoiceCommand.connectDevice);
      expect(outcome.spoken.toLowerCase(), isNot(contains('searching')));
      expect(outcome.spoken.toLowerCase(), isNot(contains('looking for')));
      expect(outcome.spoken, contains('not built yet'));
    });
  });

  group('cancel outside a countdown', () {
    test('stops the app talking, and says nothing over it', () async {
      final outcome = await actions().handle(VoiceCommand.cancel);
      expect(outcome.stopSpeaking, isTrue);
      expect(outcome.route, isNull);
    });
  });

  group('hands-free, by voice', () {
    test('switches it, and says which way', () async {
      final set = <bool>[];
      final a = VoiceActions(
        location: const _Source(LocationAvailability.denied),
        fetchFix: () async =>
            (availability: LocationAvailability.denied, summary: null),
        setHandsFree: (on) async => set.add(on),
      );
      expect((await a.handle(VoiceCommand.handsFreeOn)).spoken,
          kHandsFreeOnSaid);
      expect((await a.handle(VoiceCommand.handsFreeOff)).spoken,
          kHandsFreeOffSaid);
      expect(set, [true, false]);
    });
  });

  test('who is here, away from Scan, opens it', () async {
    final outcome = await actions().handle(VoiceCommand.whoIsHere);
    expect(outcome.route, Routes.scan);
  });
}
