import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/app/theme.dart';
import 'package:impairgency/core/alerts/alert_presenter.dart';
import 'package:impairgency/core/alerts/sos_alert.dart';
import 'package:impairgency/core/guardian/watched_user.dart';
import 'package:impairgency/core/location/location_fix.dart';
import 'package:impairgency/core/location/location_source.dart';
import 'package:impairgency/core/navigation/destination.dart';
import 'package:impairgency/core/navigation/map_services.dart';
import 'package:impairgency/core/navigation/place_search.dart';
import 'package:impairgency/core/navigation/route.dart';
import 'package:impairgency/core/safety/safety_notice.dart';
import 'package:impairgency/core/session_store.dart';
import 'package:impairgency/core/speech/speaker.dart';
import 'package:impairgency/core/vision/faces.dart';
import 'package:impairgency/core/vision/friend_recognition.dart';
import 'package:impairgency/core/voice/speech_recognizer.dart';
import 'package:impairgency/data/account_status_repository.dart';
import 'package:impairgency/data/auth_service.dart';
import 'package:impairgency/data/guardian_onboarding.dart';
import 'package:impairgency/data/guardian_repository.dart';
import 'package:impairgency/data/pairing_repository.dart';
import 'package:impairgency/guardian/guardian_registration.dart';
import 'package:impairgency/guardian/screens/guardian_home_page.dart';
import 'package:impairgency/vi/onboarding/verify_email_screen.dart';

import '../core/navigation/map_fixtures.dart' as map;
import '../core/vision/friend_fakes.dart';
import '../vi/voice_fakes.dart';

/// Drives the real router rather than its pieces.
///
/// Every one of these covers a gap that unit tests could not see: the redirect
/// rule and the screens were each correct on their own, and the app still stuck
/// on its first screen. That bug reached a simulator.
Future<AppSession> pumpApp(
  WidgetTester tester, {
  bool acknowledged = false,
}) async {
  final session = AppSession(
    store: InMemorySessionStore(acknowledged: acknowledged),
  );
  await session.load();
  await tester.pumpWidget(MaterialApp.router(
    theme: buildAppTheme(),
    routerConfig: createRouter(session),
  ));
  await tester.pumpAndSettle();
  return session;
}

void main() {
  testWidgets('a first run opens on the safety notice', (tester) async {
    await pumpApp(tester);
    expect(find.text(kSafetyNotice.headline), findsOneWidget);
  });

  testWidgets('acknowledging actually moves the user on', (tester) async {
    // The bug this exists for: resolveRedirect deliberately allows /safety once
    // acknowledged, so the dashboard can reopen it - which meant nothing moved
    // the user off it on first run. Both halves were right; the app was stuck.
    final session = await pumpApp(tester);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(session.state.safetyAcknowledged, isTrue);
    expect(find.text(kSafetyNotice.headline), findsNothing,
        reason: 'the notice should not still be on screen');
    expect(find.text('Welcome to ImpairGency'), findsOneWidget,
        reason: 'the real welcome screen, not a placeholder');
  });

  testWidgets('the acknowledgement is remembered across a restart',
      (tester) async {
    final session = await pumpApp(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Same store, fresh router - what a relaunch looks like.
    final relaunched = AppSession(store: session.store);
    await relaunched.load();
    await tester.pumpWidget(MaterialApp.router(
      theme: buildAppTheme(),
      routerConfig: createRouter(relaunched),
    ));
    await tester.pumpAndSettle();

    expect(find.text(kSafetyNotice.headline), findsNothing);
  });

  testWidgets('an already-acknowledged user never sees it again',
      (tester) async {
    await pumpApp(tester, acknowledged: true);
    expect(find.text(kSafetyNotice.headline), findsNothing);
    expect(find.text('Welcome to ImpairGency'), findsOneWidget);
  });

  testWidgets('the notice can be reopened later without being re-acknowledged',
      (tester) async {
    // The notice promises "you can hear this again at any time", so reopening
    // it must not put the user back through onboarding.
    final session = await pumpApp(tester, acknowledged: true);
    final router = createRouter(session);
    await tester.pumpWidget(MaterialApp.router(
      theme: buildAppTheme(),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    router.go(Routes.safety);
    await tester.pumpAndSettle();

    expect(find.text(kSafetyNotice.headline), findsOneWidget);
    expect(find.text('BACK TO MAIN SCREEN'), findsOneWidget);
    expect(find.text('I UNDERSTAND'), findsNothing);
  });

  testWidgets('a guardian whose registration works lands on their dashboard',
      (tester) async {
    // The tester's report, through the real router: the code was right and
    // the account was made, and the screen did not move - because the
    // redirect lets a signed-in guardian stay on the registration form.
    late AppSession session;
    session = AppSession(
      store: InMemorySessionStore(acknowledged: true),
      guardianOnboarding: _SigningInOnboarding(() => session),
      guardian: _NoWatchedUsers(),
      alerts: RecordingAlertPresenter(),
    );
    await session.load();
    final router = createRouter(session);
    await tester.pumpWidget(MaterialApp.router(
      theme: buildAppTheme(),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    router.go(Routes.guardianRegister);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Ben');
    await tester.enterText(fields.at(1), 'ben@example.com');
    await tester.enterText(fields.at(2), 'longenough');
    await tester.enterText(fields.at(3), '0917 000 0000');
    await tester.enterText(fields.at(4), 'FH29MR47');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.byType(GuardianHomePage), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
  });

  testWidgets('a new account waits at Check your email, then moves on',
      (tester) async {
    // The tester's made-up email got straight in. Through the real router:
    // a new, unconfirmed account is held, and confirming lets it through.
    final auth = _ScriptedAuth();
    final session = AppSession(
      store: InMemorySessionStore(acknowledged: true),
      auth: auth,
    );
    await session.load();
    await session.bindAuth();
    await tester.pumpWidget(MaterialApp.router(
      theme: buildAppTheme(),
      routerConfig: createRouter(session),
    ));
    await tester.pumpAndSettle();

    auth.emit(AuthAccount(
      uid: 'new-1',
      email: 'ben@example.com',
      createdAt: DateTime.now(),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyEmailScreen), findsOneWidget);

    auth.check = VerificationCheck.verified;
    await tester.tap(find.text('I have confirmed my email'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyEmailScreen), findsNothing);
    expect(session.state.needsEmailVerification, isFalse);
  });

  testWidgets('an account from before the cutoff is not held', (tester) async {
    final auth = _ScriptedAuth();
    final session = AppSession(
      store: InMemorySessionStore(acknowledged: true),
      auth: auth,
    );
    await session.load();
    await session.bindAuth();
    await tester.pumpWidget(MaterialApp.router(
      theme: buildAppTheme(),
      routerConfig: createRouter(session),
    ));
    await tester.pumpAndSettle();

    auth.emit(AuthAccount(
      uid: 'old-1',
      email: 'demo@example.com',
      createdAt: DateTime.utc(2026, 9, 1),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyEmailScreen), findsNothing);
    expect(session.state.needsEmailVerification, isFalse);
  });

  test('a removed account is signed out, and told why once', () async {
    // An administrator removed it from the dashboard. The phone deletes what
    // only its owner may, signs out, and says so - the welcome screen repeats
    // it once, not on every visit.
    final auth = _ScriptedAuth()
      ..emit(const AuthAccount(uid: 'u1', email: 'u1@example.com'));
    final said = <String>[];
    final session = AppSession(
      store: InMemorySessionStore(acknowledged: true),
      auth: auth,
      speaker: _Recording(said),
    );

    await session.handleRemoval('u1');

    expect(auth.isSignedIn, isFalse);
    expect(said, [kRemovedAccountNotice]);
    expect(session.takeNotice(), kRemovedAccountNotice);
    expect(session.takeNotice(), isNull);
  });

  group('friends', () {
    Friend friend(String name) => Friend(
        id: 'id-$name',
        name: name,
        embeddings: const [
          [1.0, 0.0]
        ],
        savedAt: DateTime(2026));

    test('turning recognition off deletes the saved faces, and says how many',
        () async {
      final said = <String>[];
      final faces = MemoryStore()..saved['local'] = [friend('Sam'), friend('Ana')];
      final session = AppSession(
        store: InMemorySessionStore(acknowledged: true),
        speaker: _Recording(said),
        friendStore: faces,
      );
      await session.load();
      await session.rememberConsent({'faces': true});
      expect(faces.saved['local'], hasLength(2), reason: 'turning it on keeps them');

      await session.rememberConsent({'faces': false});
      expect(faces.saved['local'], isNull);
      expect(said.last, 'The 2 saved faces on this phone were deleted.');
    });

    test('signing out deletes the faces kept for the account', () async {
      final auth = _ScriptedAuth();
      final faces = MemoryStore()..saved['u1'] = [friend('Sam')];
      final session = AppSession(
        store: InMemorySessionStore(acknowledged: true),
        auth: auth,
        friendStore: faces,
      );
      await session.load();
      await session.bindAuth();
      auth.emit(const AuthAccount(uid: 'u1', email: 'u1@example.com'));
      await pumpEventQueue();
      expect(session.state.uid, 'u1');

      await session.signOut();
      expect(faces.saved['u1'], isNull);
    });

    test('"hello friend Sam" elsewhere opens scan to meet Sam - with consent',
        () async {
      final session = AppSession(
        store: InMemorySessionStore(acknowledged: true),
        friendStore: MemoryStore(),
      );
      await session.load();
      expect((await session.rememberFriend('sam')).spoken, kFacesOffPhrase);
      expect(session.takePendingFriend(), isNull);

      await session.rememberConsent({'faces': true});
      final outcome = await session.rememberFriend('sam');
      expect(outcome.route, Routes.scan);
      expect(session.takePendingFriend(), 'Sam');
      expect(session.takePendingFriend(), isNull, reason: 'met once');
      expect(session.friendRecognition(), isNotNull);
    });
  });

  group('by voice', () {
    const home = Destination(
        id: 'home', label: 'Home', latitude: 14.79, longitude: 120.92,
        kind: DestinationKind.home);
    const clinic =
        Destination(id: 'p1', label: 'Clinic', latitude: 14.8, longitude: 120.93);

    test('"dalhin ako sa bahay" opens Scan with directions to Home', () async {
      final store = InMemorySessionStore(acknowledged: true);
      await store.cachePlaces(const [clinic, home]);
      final session = AppSession(store: store);
      await session.load();

      final outcome = await session.goTo('bahay');
      expect(outcome.route, Routes.scan);
      expect(outcome.spoken, 'Directions to Home.');
      expect(session.destination, home);

      await session.goTo('the clinic');
      expect(session.destination, clinic);
    });

    test('a place that is not saved is said, and nothing is guessed', () async {
      final store = InMemorySessionStore(acknowledged: true);
      await store.cachePlaces(const [clinic, home]);
      final session = AppSession(store: store);
      await session.load();

      final outcome = await session.goTo('Jollibee');
      expect(outcome.route, Routes.assist);
      expect(outcome.spoken,
          contains('could not find a saved place called Jollibee'));
      expect(session.destination, isNull);
    });

    group('a place that is not saved', () {
      late OpenWindows mic;
      late List<String> said;
      late _Places search;
      late AppSession session;

      setUp(() async {
        mic = OpenWindows();
        said = [];
        search = _Places();
        session = AppSession(
          store: InMemorySessionStore(acknowledged: true),
          speaker: _Recording(said),
          recognizer: mic,
          placeSearch: search,
          location: _At(map.a),
        );
        await session.load();
        session.voice; // the questions are asked through it
      });

      test('is looked up nearby, and each place found offered in turn',
          () async {
        final outcome = session.goTo('jollibee');
        await pumpEventQueue();
        expect(said.first, 'Looking for jollibee nearby.');
        expect(said.last,
            'Jollibee, Paseo del Congreso, Malolos, about 600 metres away. '
            'Say yes to go there, next for another, or no.');
        expect(search.near, map.a);

        await mic.hear(const Heard('next'));
        expect(said.last, startsWith('Jollibee, MacArthur Highway, Longos'));
        expect(said.last, endsWith('Say yes to go there, or no.'),
            reason: 'the last one found; Makati was too far to offer');

        await mic.hear(const Heard('yes'));
        final result = await outcome;
        expect(result.route, Routes.scan);
        expect(result.spoken, 'Directions to Jollibee.');
        expect(session.destination?.id, 'search-N3333');
      });

      test('no, or no answer, chooses nothing', () async {
        final outcome = session.goTo('jollibee');
        await pumpEventQueue();
        await mic.hear(const NotHeard(VoiceInputFailure.nothingHeard));
        final result = await outcome;
        expect(result.spoken, 'Nothing was chosen.');
        expect(result.route, isNull);
        expect(session.destination, isNull);
      });

      test('no connection is said, and nothing is opened', () async {
        search.failure = MapServiceFailure.offline;
        final result = await session.goTo('jollibee');
        expect(result.spoken, contains('needs an internet connection'));
        expect(result.route, isNull);
      });

      test('"where am I" names the street', () async {
        final heard = session.voice.listen();
        await pumpEventQueue();
        await mic.hear(const Heard('where am I'));
        await heard;
        expect(said.last,
            'You are near Rizal Street, Malolos, accurate to about 10 metres.');
      });
    });

    test('the hands-free switch is kept on this phone', () async {
      final store = InMemorySessionStore(acknowledged: true);
      final session = AppSession(store: store);
      await session.load();
      await session.setHandsFree(false);

      final relaunched = AppSession(store: store);
      await relaunched.load();
      expect(relaunched.handsFree, isFalse);

      await relaunched.setHandsFree(true);
      final again = AppSession(store: store);
      await again.load();
      expect(again.handsFree, isTrue);
    });
  });
}

/// Registration that succeeds the way Firebase would: the guardian ends up
/// signed in, and the router hears about it.
class _SigningInOnboarding implements GuardianOnboarding {
  _SigningInOnboarding(this.session);

  final AppSession Function() session;

  @override
  Future<RegisterFailure?> register(GuardianRegistration registration) async {
    session().update(const SessionState(
      uid: 'guardian-1',
      signedIn: true,
      isGuardian: true,
      safetyAcknowledged: true,
    ));
    return null;
  }

  @override
  Future<String?> redeem(String code) async => null;
  @override
  AuthService get auth => throw UnimplementedError();
  @override
  SessionStore get store => throw UnimplementedError();
  @override
  PairingRepository get pairing => throw UnimplementedError();
  @override
  GuardianProfileStore get profiles => throw UnimplementedError();
}

class _NoWatchedUsers implements GuardianRepository {
  @override
  Stream<List<WatchedUser>> watch(String guardianId) =>
      Stream.value(const <WatchedUser>[]);
  @override
  Stream<List<SosEvent>> sosFeed(String guardianId) =>
      Stream.value(const <SosEvent>[]);
  @override
  Stream<List<SosEvent>> recentSosEvents(String uid) =>
      Stream.value(const <SosEvent>[]);
}

/// Firebase Auth reduced to what the router listens to, driven by the test.
class _ScriptedAuth implements AuthService {
  final _accounts = StreamController<AuthAccount?>.broadcast();
  AuthAccount? _current;
  VerificationCheck check = VerificationCheck.notYet;

  void emit(AuthAccount account) {
    _current = account;
    _accounts.add(account);
  }

  @override
  Stream<AuthAccount?> get accounts => _accounts.stream;
  @override
  String? get uid => _current?.uid;
  @override
  String? get email => _current?.email;
  @override
  bool get isSignedIn => _current != null;
  @override
  bool get isEmailVerified => check == VerificationCheck.verified;
  @override
  bool? verificationSent = true;
  @override
  Stream<User?> get changes => const Stream.empty();
  @override
  Future<VerificationCheck> checkVerification() async => check;
  @override
  Future<String?> sendVerification() async => null;
  @override
  Future<String?> signIn(String email, String password) async => null;
  @override
  Future<AuthFailure?> createAccount(String email, String password) async =>
      null;
  @override
  Future<String?> sendPasswordReset(String email) async => null;
  @override
  Future<void> resendVerification() async {}
  @override
  Future<bool> refreshVerification() async => isEmailVerified;
  @override
  Future<void> signOut() async {
    _current = null;
    _accounts.add(null);
  }
}

class _Recording implements Speaker {
  _Recording(this.said);
  final List<String> said;
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

class _Places implements PlaceSearchService {
  RoutePoint? near;
  MapServiceFailure? failure;

  @override
  Future<List<PlaceCandidate>> search(String query,
      {required RoutePoint near}) async {
    this.near = near;
    final failure = this.failure;
    if (failure != null) throw MapServiceException(failure);
    return parsePhoton(map.photonJollibee);
  }

  @override
  Future<PlaceCandidate?> reverse(RoutePoint point) async =>
      parsePhoton(map.photonReverseAtA).first;
}

class _At implements LocationSource {
  const _At(this.point);
  final RoutePoint point;

  LocationFix get _fix => LocationFix(
      latitude: point.latitude,
      longitude: point.longitude,
      accuracyMetres: 8,
      at: DateTime.now());

  @override
  Future<LocationAvailability> availability() async =>
      LocationAvailability.ready;
  @override
  Future<LocationAvailability> requestPermission() async =>
      LocationAvailability.ready;
  @override
  Future<LocationFix?> currentFix({Duration timeout = Duration.zero}) async =>
      _fix;
  @override
  Future<LocationFix?> lastKnownFix() async => _fix;
}
