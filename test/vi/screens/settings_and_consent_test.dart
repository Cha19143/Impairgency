import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/places/place.dart';
import 'package:impairgency/core/places/stay.dart';
import 'package:impairgency/core/session_store.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/vi/onboarding/consent_screen.dart';
import 'package:impairgency/vi/screens/consent_centre_screen.dart';
import 'package:impairgency/vi/screens/learned_data_screen.dart';
import 'package:impairgency/vi/screens/settings_screen.dart';
import 'package:impairgency/vi/widgets/vi_button.dart';

class RecordingSpeaker implements Speaker {
  final List<String> said = [];
  @override
  String? get lastSpoken => said.isEmpty ? null : said.last;
  @override
  Future<void> repeat() async {}
  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> speakLines(List<String> lines) async => said.addAll(lines);
  @override
  Future<void> stop() async {}
}

/// Scrolls a control into view before tapping it.
///
/// The actions area scrolls when a screen has more choices than fit, so a
/// finder can resolve to something off-screen. A real user scrolls; so does
/// this.
Future<void> tapAction(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: child));
  await tester.pump();
}

void main() {
  group('settings (#53) — everything skippable can be done later', () {
    testWidgets('offers device connection outside onboarding', (tester) async {
      // §5 asks for it "during registration or through the application's
      // homepage/settings". ui.pdf only had registration.
      var tapped = false;
      await pump(
        tester,
        SettingsScreen(
          onConsent: () {}, onLearned: () {},
          onDevice: () => tapped = true,
          onEmergencyContact: () {}, onInviteGuardian: () {},
          onSafetyNotice: () {}, onBack: () {},
        ),
      );
      await tapAction(tester, find.text('Connect a device'));
      expect(tapped, isTrue);
    });

    testWidgets('a missing emergency contact is flagged, not hidden',
        (tester) async {
      await pump(
        tester,
        SettingsScreen(
          hasContact: false,
          onConsent: () {}, onLearned: () {}, onDevice: () {},
          onEmergencyContact: () {}, onInviteGuardian: () {},
          onSafetyNotice: () {}, onBack: () {},
        ),
      );
      expect(find.text('Not set. SOS has nobody to call.'), findsOneWidget);

      final button = tester.widgetList<ViButton>(find.byType(ViButton)).first;
      expect(button.kind, ViButtonKind.emergency,
          reason: 'it should look as urgent as it is');
    });

    testWidgets('the safety notice stays reachable', (tester) async {
      // The notice promises "you can hear this again at any time".
      var opened = false;
      await pump(
        tester,
        SettingsScreen(
          onConsent: () {}, onLearned: () {}, onDevice: () {},
          onEmergencyContact: () {}, onInviteGuardian: () {},
          onSafetyNotice: () => opened = true, onBack: () {},
        ),
      );
      await tapAction(tester, find.text('What this app can and cannot do'));
      expect(opened, isTrue);
    });
  });

  group('consent centre (#51)', () {
    testWidgets('shows what is on now', (tester) async {
      await pump(
        tester,
        ConsentCentreScreen(
          current: const {'location': true},
          onSave: (_) async {},
          onBack: () {},
        ),
      );
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.first.value, isTrue);
      expect(switches.skip(1).every((s) => s.value == false), isTrue);
    });

    testWidgets('says nothing is shared when nothing is', (tester) async {
      await pump(
        tester,
        ConsentCentreScreen(
          current: const {},
          onSave: (_) async {},
          onBack: () {},
        ),
      );
      expect(find.textContaining('Nothing about you is being shared'),
          findsOneWidget);
      expect(find.text('Turn everything off'), findsNothing,
          reason: 'there is nothing to turn off');
    });

    testWidgets('turns everything off in one action', (tester) async {
      Map<String, bool>? saved;
      await pump(
        tester,
        ConsentCentreScreen(
          current: const {'location': true, 'history': true},
          onSave: (v) async => saved = v,
          onBack: () {},
        ),
      );
      await tapAction(tester, find.text('Turn everything off'));
      await tapAction(tester, find.text('Save'));

      expect(saved!.values.every((v) => v == false), isTrue);
    });

    testWidgets('uses the same words as the onboarding consent screen',
        (tester) async {
      // What was agreed to and what can be revoked must be described
      // identically, or a user cannot tell they are the same thing.
      await pump(
        tester,
        ConsentCentreScreen(
          current: const {},
          onSave: (_) async {},
          onBack: () {},
        ),
      );
      for (final choice in kConsentChoices) {
        expect(find.text(choice.title), findsOneWidget, reason: choice.key);
      }
    });

    testWidgets('leaving without saving changes nothing', (tester) async {
      var saved = false;
      var backed = false;
      await pump(
        tester,
        ConsentCentreScreen(
          current: const {'location': true},
          onSave: (_) async => saved = true,
          onBack: () => backed = true,
        ),
      );
      await tapAction(tester, find.text('Back without saving'));

      expect(backed, isTrue);
      expect(saved, isFalse);
    });
  });

  group('what the app has learned (#52)', () {
    Place place({String? label, int visits = 3}) => Place(
          latitude: 14.79,
          longitude: 120.92,
          label: label,
          visits: [
            for (var i = 0; i < visits; i++)
              Stay(
                latitude: 14.79,
                longitude: 120.92,
                arrived: DateTime.utc(2026, 9, 1 + i, 8),
                departed: DateTime.utc(2026, 9, 1 + i, 16),
                fixCount: 20,
              ),
          ],
        );

    testWidgets('lists places with their visit counts', (tester) async {
      await pump(
        tester,
        LearnedDataScreen(
          places: [place(label: 'Home', visits: 5)],
          onForgetAll: () async {},
          onForgetPlace: (_) async {},
          onBack: () {},
        ),
      );
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('5 visits'), findsOneWidget);
    });

    testWidgets('never presents an app-invented name', (tester) async {
      await pump(
        tester,
        LearnedDataScreen(
          places: [place()],
          onForgetAll: () async {},
          onForgetPlace: (_) async {},
          onBack: () {},
        ),
      );
      expect(find.text('A place you go often'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('can forget one place, or all of it', (tester) async {
      var forgotAll = false;
      Place? forgotten;
      await pump(
        tester,
        LearnedDataScreen(
          places: [place(label: 'Clinic')],
          onForgetAll: () async => forgotAll = true,
          onForgetPlace: (p) async => forgotten = p,
          onBack: () {},
        ),
      );
      await tapAction(tester, find.text('Forget this place'));
      expect(forgotten, isNotNull);

      await tapAction(tester, find.text('Forget everything'));
      expect(forgotAll, isTrue);
    });

    testWidgets('an empty list explains why rather than showing nothing',
        (tester) async {
      await pump(
        tester,
        LearnedDataScreen(
          places: const [],
          onForgetAll: () async {},
          onForgetPlace: (_) async {},
          onBack: () {},
        ),
      );
      expect(find.textContaining('only remembers where you go if you have '
          'turned that on'), findsOneWidget);
      expect(find.text('Forget everything'), findsNothing);
    });
  });

  group('offline-tolerant first run (#54)', () {
    test('everything the dashboard needs comes from local storage', () async {
      // A returning user with no signal must still reach a working SOS.
      final store = InMemorySessionStore(
        acknowledged: true,
        steps: Routes.onboardingFlow.toSet(),
        profile: const CachedProfile(
          consent: {'location': true},
          contactName: 'Mum',
          contactNumber: '+639171234567',
          guardianCount: 1,
        ),
      );

      final session = AppSession(store: store);
      await session.load();

      expect(session.state.safetyAcknowledged, isTrue);
      expect(session.state.setupComplete, isTrue);
      expect(session.state.contactNumber, '+639171234567');
      expect(session.state.guardianCount, 1);
      expect(session.state.consent['location'], isTrue);
    });

    test('a fresh install offline still reaches the safety notice', () async {
      final session = AppSession(store: InMemorySessionStore());
      await session.load();
      expect(
        resolveRedirect(
            isWeb: false, location: Routes.home, session: session.state),
        Routes.safety,
      );
    });

    test('a set-up user offline is sent to the dashboard, not onboarding',
        () async {
      final session = AppSession(
        store: InMemorySessionStore(
          acknowledged: true,
          steps: Routes.onboardingFlow.toSet(),
        ),
      );
      await session.load();
      session.update(SessionState(
        uid: 'u1',
        signedIn: true,
        safetyAcknowledged: true,
        completedSteps: Routes.onboardingFlow.toSet(),
      ));

      expect(
        resolveRedirect(
            isWeb: false, location: Routes.home, session: session.state),
        isNull,
      );
    });
  });
}
