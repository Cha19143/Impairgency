import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/alerts/alert_presenter.dart';
import '../core/contacts/emergency_contact.dart';
import '../core/location/location_policy.dart';
import '../core/location/location_source.dart';
import '../core/navigation/destination.dart';
import '../core/places/session_event.dart';
import '../core/places/place.dart';
import '../core/session_store.dart';
import '../core/speech/speaker.dart';
import '../core/voice/speech_recognizer.dart';
import '../admin/screens/accessibility_screen.dart';
import '../admin/screens/admin_page.dart';
import '../admin/screens/admin_shell.dart';
import '../admin/screens/admin_sign_in_screen.dart';
import '../admin/screens/invite_dialog.dart';
import '../admin/screens/overview_screen.dart';
import '../admin/screens/system_health_screen.dart';
import '../admin/screens/users_screen.dart';
import '../core/places/session_summary.dart';
import '../data/admin_repository.dart';
import '../data/auth_service.dart';
import '../data/contact_picker.dart';
import '../data/geolocator_location_source.dart';
import '../data/guardian_onboarding.dart';
import '../data/guardian_repository.dart';
import '../data/local_alert_presenter.dart';
import '../data/pairing_repository.dart';
import '../data/saved_places_repository.dart';
import '../data/location_history_repository.dart';
import '../data/sos_engine.dart';
import '../data/stt_speech_recognizer.dart';
import '../guardian/screens/accept_invitation_screen.dart';
import '../guardian/screens/guardian_home_page.dart';
import '../guardian/screens/guardian_register_screen.dart';
import '../shared/widgets/pending_screen.dart';
import '../vi/onboarding/all_set_screen.dart';
import '../vi/onboarding/choose_role_screen.dart';
import '../vi/onboarding/forgot_password_screen.dart';
import '../vi/onboarding/profile_screen.dart';
import '../vi/onboarding/consent_screen.dart';
import '../vi/onboarding/create_account_screen.dart';
import '../vi/onboarding/device_screen.dart';
import '../vi/onboarding/emergency_contact_screen.dart';
import '../vi/onboarding/invite_guardian_screen.dart';
import '../vi/onboarding/onboarding_controller.dart';
import '../vi/onboarding/preferences_screen.dart';
import '../vi/onboarding/sign_in_screen.dart';
import '../vi/onboarding/welcome_screen.dart';
import '../vi/screens/consent_centre_screen.dart';
import '../vi/screens/dashboard_screen.dart';
import '../vi/screens/learned_data_screen.dart';
import '../vi/screens/scan_screen.dart';
import '../vi/screens/settings_screen.dart';
import '../vi/screens/sign_out_screen.dart';
import '../vi/screens/location_debug_screen.dart';
import '../vi/screens/sos_flow.dart';
import '../vi/screens/what_can_i_say_screen.dart';
import '../vi/screens/safety_notice_screen.dart';
import '../vi/screens/saved_places_screen.dart';
import '../vi/screens/smart_assistance_screen.dart';
import '../vi/voice_actions.dart';
import '../vi/voice_controller.dart';
import '../vi/widgets/vi_button.dart';
import '../vi/widgets/vi_screen.dart';
import 'routes.dart';

/// Live session, fed by FirebaseAuth once `flutterfire configure` has been run
/// against the new project. Until then it reports signed out, which is the
/// correct default: the guard fails closed.
class AppSession extends ChangeNotifier {
  AppSession({
    SessionStore? store,
    Speaker? speaker,
    PairingRepository? pairing,
    SpeechRecognizer? recognizer,
  })  : store = store ?? InMemorySessionStore(),
        speaker = speaker ?? const SilentSpeaker(),
        _pairing = pairing,
        _recognizer = recognizer;

  final SessionStore store;
  final Speaker speaker;

  /// [speaker], with priorities. The scan screen needs them; a test that
  /// passed a plain recording speaker gets it back wrapped.
  PrioritySpeaker get prioritySpeaker => withPriorities(speaker);

  SpeechRecognizer? _recognizer;

  /// Where a spoken command sends the user. Set by [createRouter].
  void Function(String route)? navigate;

  VoiceController? _voice;

  /// The microphone, and everything between it and an action.
  ///
  /// One for the whole app rather than one per screen, so the permission is
  /// asked for once, the failure is explained once, and a screen that opens
  /// while another is listening does not end up with two microphones.
  VoiceController get voice => _voice ??= VoiceController(
        recognizer: _recognizer ??= SttSpeechRecognizer(),
        speaker: speaker,
        actions: () => VoiceActions(
          location: const GeolocatorLocationSource(),
          fetchFix: _fixForVoice,
          contactName: _state.contactName,
          hasGuardian: _state.guardianCount > 0,
        ),
        onNavigate: (route) => navigate?.call(route),
      );

  /// What "where am I" reads back: the SOS location policy's sentence, so the
  /// answer carries the same honesty about age and accuracy.
  Future<({LocationAvailability availability, String? summary})>
      _fixForVoice() async {
    const source = GeolocatorLocationSource();
    final availability = await source.requestPermission();
    if (availability != LocationAvailability.ready) {
      return (availability: availability, summary: null);
    }
    final fix = await bestEffortFix(source);
    final outcome = resolveLocationForSos(
      availability: availability,
      fix: fix,
      now: DateTime.now(),
    );
    return (
      availability: availability,
      summary: outcome.hasSomethingToSend ? outcome.spoken : null,
    );
  }

  // Constructed lazily so a widget test that never opens a Firestore-backed
  // screen does not need Firebase initialised.
  PairingRepository? _pairing;
  PairingRepository get pairing => _pairing ??= PairingRepository();

  AlertPresenter? _alerts;
  AlertPresenter get alerts => _alerts ??= LocalAlertPresenter();

  AdminRepository? _admin;
  AdminRepository get admin => _admin ??= AdminRepository();

  AuthService? _auth;
  AuthService get auth => _auth ??= AuthService();

  LocationHistoryRepository? _history;
  LocationHistoryRepository get history =>
      _history ??= LocationHistoryRepository();

  SosEngine? _sos;
  SosEngine get sos => _sos ??= SosEngine(speaker: speaker);

  SavedPlacesRepository? _places;
  SavedPlacesRepository get places =>
      _places ??= SavedPlacesRepository(store: store);

  /// Where the user has said they are going. Cleared when they arrive or
  /// stop, and by sign-out. In memory only: a destination is for a journey,
  /// not a setting.
  Destination? destination;

  /// Records the destination the way §2.A.7 records a journey, and remembers
  /// it for the scan screen. Best effort on the record: it needs history
  /// consent and a connection, and the directions need neither.
  Future<void> setDestination(Destination? place) async {
    destination = place;
    notifyListeners();
    final uid = _state.uid;
    if (place == null || uid == null) return;
    try {
      await history.recordEvent(
        uid,
        sessionId: 'journey-${DateTime.now().millisecondsSinceEpoch}',
        kind: SessionEventKind.destinationSet,
        detail: place.label,
      );
    } catch (_) {
      // No consent, or no network. The directions do not depend on it.
    }
  }

  GuardianRepository? _guardian;
  GuardianRepository get guardian =>
      _guardian ??= GuardianRepository(pairing: pairing);

  GuardianOnboarding? _guardianOnboarding;
  GuardianOnboarding get guardianOnboarding =>
      _guardianOnboarding ??= GuardianOnboarding(
        auth: auth,
        store: store,
        pairing: pairing,
      );

  OnboardingController? _onboarding;
  OnboardingController get onboarding => _onboarding ??= OnboardingController(
        auth: auth,
        store: store,
        pairing: pairing,
      );

  /// Follows Firebase auth so the router's guard reflects who is signed in.
  ///
  /// Called from app.dart once Firebase is up. Left uncalled in tests, where
  /// the session stays signed out - which is the guard failing closed.
  Future<void> bindAuth() async {
    auth.changes.listen((user) async {
      if (user == null) {
        // Read back off the device rather than carrying the old state
        // forward. Signing out clears what this phone held about that account,
        // and a listener that trusted its own memory would put it straight
        // back - including the safety acknowledgement, which belongs to the
        // person who heard the notice and not to the handset.
        update(SessionState(
          safetyAcknowledged: await store.safetyAcknowledged(),
          completedSteps: await store.completedSteps(),
        ));
        return;
      }
      final isAdmin = await admin.isAdmin(user.uid);
      // Which app this account is for, decided before the guard runs: a
      // guardian sent through the visually impaired flow would be asked to
      // create the account they have just created.
      final isGuardian = await _isGuardian(user.uid);
      update(SessionState(
        uid: user.uid,
        consent: _state.consent,
        contacts: _state.contacts,
        guardianCount: _state.guardianCount,
        signedIn: true,
        isAdmin: isAdmin,
        isGuardian: isGuardian,
        safetyAcknowledged: _state.safetyAcknowledged,
        completedSteps: _state.completedSteps,
      ));
      // Best effort, and deliberately not awaited by the guard.
      unawaited(refreshProfile());
    });
  }

  SessionState _state = const SessionState();
  SessionState get state => _state;

  /// Reads what was persisted before the first frame decides where to go.
  ///
  /// Everything here is local. A returning user with no signal reaches their
  /// dashboard with the alarm and the dialler live, because nothing on this
  /// path needs Firestore.
  Future<void> load() async {
    final profile = await store.cachedProfile();
    update(SessionState(
      uid: _state.uid,
      signedIn: _state.signedIn,
      isAdmin: _state.isAdmin,
      isGuardian: _state.isGuardian || profile.isGuardian,
      safetyAcknowledged: await store.safetyAcknowledged(),
      completedSteps: await store.completedSteps(),
      consent: profile.consent,
      contacts: profile.contacts,
      guardianCount: profile.guardianCount,
    ));
  }

  /// Re-reads the profile from Firestore and caches it.
  ///
  /// Failure is not an error: the cached values stay, which is the whole point.
  Future<void> refreshProfile() async {
    final uid = _state.uid;
    if (uid == null) return;
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snapshot.data();
      if (data == null) return;
      await store.cacheProfile(CachedProfile(
        role: data['role'] as String?,
        consent: Map<String, bool>.from(data['consent'] as Map? ?? const {}),
        contacts: emergencyContactsFrom(data),
        guardianCount: await _countGuardians(uid),
      ));
      await load();
    } catch (_) {
      // Offline. The cache is what the app runs on until the network returns.
    }
  }

  /// Counted from the pairings, because nothing on the client may write a
  /// count onto the user document and nothing on the server does either.
  /// Falls back to what was cached rather than to zero: offline, "no
  /// guardian" would be a claim, and the wrong one.
  Future<int> _countGuardians(String uid) async {
    try {
      return (await pairing.guardiansOf(uid)).length;
    } catch (_) {
      return _state.guardianCount;
    }
  }

  /// The role, from the device first and the account second.
  ///
  /// The device's copy is written before an account is created and cleared
  /// at sign-out, so it is right whenever it is present. The account is read
  /// only when it is not - a sign-in on a new phone - and bounded, because
  /// this runs before the first screen and a phone with no signal must still
  /// reach one.
  Future<bool> _isGuardian(String uid) async {
    final cached = await store.cachedProfile();
    if (cached.role != null) return cached.isGuardian;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 6));
      final role = snapshot.data()?['role'] as String?;
      if (role != null) await store.cacheProfile(cached.copyWith(role: role));
      return role == 'guardian';
    } catch (_) {
      return false;
    }
  }

  /// Records which app a new account is for, before it is created.
  Future<void> rememberRole(String role) async {
    final cached = await store.cachedProfile();
    await store.cacheProfile(cached.copyWith(role: role));
    await load();
  }

  /// Puts a just-saved emergency contact where SOS reads it from.
  ///
  /// The bug this closes: the contact was written to Firestore and the
  /// device's copy - the one SOS and Settings actually read - was refreshed
  /// only at sign-in. Save a contact during setup, press SOS, and the
  /// receipt said no contact was saved. The tester was right that the
  /// feature did not work; it worked on the next launch, with a network.
  Future<void> rememberContacts(List<EmergencyContact> contacts) async {
    final cached = await store.cachedProfile();
    await store.cacheProfile(cached.copyWith(contacts: dedupeContacts(contacts)));
    await load();
  }

  /// Same shape, for consent. The consent centre used to re-read Firestore
  /// after saving, which offline meant a switch that did not move.
  Future<void> rememberConsent(Map<String, bool> consent) async {
    final cached = await store.cachedProfile();
    await store.cacheProfile(cached.copyWith(consent: consent));
    await load();
  }

  void update(SessionState next) {
    _state = next;
    notifyListeners();
  }

  /// Runs an onboarding step's work, then re-reads what is complete.
  ///
  /// The redirect sends the user to the first incomplete step, so refreshing
  /// the session *is* the navigation - there is no second source of truth for
  /// where they are in the flow.
  Future<void> advance(Future<void> Function() work) async {
    await work();
    await load();
  }

  /// Signs out, and hands the phone back the way it was found.
  ///
  /// Firebase first, because it is the only step here that can fail. Clearing
  /// the device before it would, on that failure, leave a phone with no setup
  /// on it still signed in to the account the setup belonged to — which lands
  /// the user back at "Create your account" for an account they already have.
  /// That is the loop this release exists to close, reached by another road.
  Future<void> signOut() async {
    await auth.signOut();
    await store.forgetAccount();
    destination = null;
    await load();
  }

  Future<void> acknowledgeSafety() async {
    await store.acknowledgeSafety();
    update(SessionState(
      signedIn: _state.signedIn,
      isAdmin: _state.isAdmin,
      isGuardian: _state.isGuardian,
      safetyAcknowledged: true,
      completedSteps: _state.completedSteps,
    ));
  }
}

/// Lets a device run start somewhere specific without editing code:
///
///     flutter run --dart-define=START=/debug
///
/// Empty by default, so nothing about the normal launch changes.
const String _startOverride = String.fromEnvironment('START');

GoRouter createRouter(AppSession session) {
  final router = GoRouter(
      initialLocation: _startOverride.isNotEmpty
          ? _startOverride
          : (kIsWeb ? Routes.adminRoot : Routes.welcome),
      refreshListenable: session,
      redirect: (context, state) => resolveRedirect(
        isWeb: kIsWeb,
        location: state.matchedLocation,
        session: session.state,
      ),
      routes: [
        // Debug builds only. Never reachable in a release binary.
        if (kDebugMode)
          GoRoute(
            path: Routes.debug,
            builder: (_, __) => LocationDebugScreen(
              source: const GeolocatorLocationSource(),
              presenter: session.alerts,
              bestEffort: bestEffortFix,
            ),
          ),
        GoRoute(
          path: Routes.safety,
          builder: (context, _) {
            // Captured before the callback runs: once acknowledged, the state
            // says true and the screen would no longer know it had been the
            // first run.
            final firstRun = !session.state.safetyAcknowledged;
            return SafetyNoticeScreen(
              speaker: session.speaker,
              alreadyAcknowledged: !firstRun,
              onAcknowledge: () async {
                await session.acknowledgeSafety();
                if (!context.mounted) return;
                // The redirect deliberately allows /safety once acknowledged,
                // so that the dashboard can reopen it. That means nothing moves
                // the user off it here - this navigation has to be explicit.
                appNavigate(context, firstRun ? Routes.welcome : Routes.home);
              },
            );
          },
        ),

        // ---- visually impaired user app (mobile) ----
        GoRoute(
          path: Routes.welcome,
          builder: (context, _) => WelcomeScreen(
            speaker: session.speaker,
            onCreateAccount: () => appNavigate(context, Routes.chooseRole),
            onSignIn: () => appNavigate(context, Routes.signIn),
          ),
        ),
        GoRoute(
          path: Routes.chooseRole,
          builder: (context, _) => ChooseRoleScreen(
            speaker: session.speaker,
            onVisuallyImpaired: () async {
              await session.rememberRole('vi');
              if (context.mounted) appNavigate(context, Routes.createAccount);
            },
            onGuardian: () => appNavigate(context, Routes.guardianRegister),
            onSignIn: () => appNavigate(context, Routes.signIn),
          ),
        ),
        GoRoute(
          path: Routes.forgotPassword,
          builder: (context, state) => ForgotPasswordScreen(
            speaker: session.speaker,
            initialEmail: state.uri.queryParameters['email'],
            onSendReset: session.auth.sendPasswordReset,
            onBack: () => appNavigate(context, Routes.signIn),
          ),
        ),
        GoRoute(
          path: Routes.signIn,
          builder: (context, _) => SignInScreen(
            speaker: session.speaker,
            onSignIn: (email, password) async {
              final failure = await session.auth.signIn(email, password);
              if (failure != null) return failure;
              // What the account has already finished, back onto this device
              // before the redirect reads it. Without this the router sees no
              // completed steps and sends a returning user to step one, to
              // create the account they have just signed in to.
              await session.onboarding.restoreProgress();
              await session.load();
              return null;
            },
            onCreateAccount: () => appNavigate(context, Routes.chooseRole),
            onForgotPassword: (email) => appNavigate(
              context,
              Uri(
                path: Routes.forgotPassword,
                queryParameters: email.isEmpty ? null : {'email': email},
              ).toString(),
            ),
          ),
        ),
        GoRoute(
          path: Routes.createAccount,
          builder: (context, _) => CreateAccountScreen(
            speaker: session.speaker,
            onCreate: (email, password) async {
              final failure =
                  await session.onboarding.createAccount(email, password);
              if (failure == null) await session.load();
              return failure;
            },
          ),
        ),
        GoRoute(
          path: Routes.profile,
          builder: (context, _) => ProfileScreen(
            speaker: session.speaker,
            onSave: (info) => session.advance(
                () => session.onboarding.savePersonalInfo(info)),
          ),
        ),
        GoRoute(
          path: Routes.preferences,
          builder: (context, _) => PreferencesScreen(
            speaker: session.speaker,
            onChoose: (on) => session.advance(
                () => session.onboarding.savePreference(screenStaysOn: on)),
            onSkip: () => session.advance(
                () => session.onboarding.skip(Routes.preferences)),
          ),
        ),
        GoRoute(
          path: Routes.emergencyContact,
          builder: (context, _) => EmergencyContactScreen(
            speaker: session.speaker,
            initial: session.state.contacts,
            picker: const SystemContactPicker(),
            onSave: (contacts) => session.advance(() async {
              await session.onboarding.saveEmergencyContacts(contacts);
              await session.rememberContacts(contacts);
            }),
            onSkip: () => session.advance(
                () => session.onboarding.skip(Routes.emergencyContact)),
          ),
        ),
        GoRoute(
          path: Routes.inviteGuardian,
          builder: (context, _) => FutureBuilder<String?>(
            future: session.onboarding.issueGuardianCode(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              final code = snapshot.data;
              if (code == null) {
                // Never a fabricated code: a guardian entering one that was
                // never issued would fail with no way to tell why.
                return _CouldNotIssueCode(
                  speaker: session.speaker,
                  onSkip: () => session.advance(
                      () => session.onboarding.skip(Routes.inviteGuardian)),
                );
              }
              return InviteGuardianScreen(
                speaker: session.speaker,
                code: code,
                onDone: () => session
                    .advance(session.onboarding.markGuardianInvited),
                onSkip: () => session.advance(
                    () => session.onboarding.skip(Routes.inviteGuardian)),
              );
            },
          ),
        ),
        GoRoute(
          path: Routes.consent,
          builder: (context, _) => ConsentScreen(
            speaker: session.speaker,
            onContinue: (values) => session.advance(() async {
              await session.onboarding.saveConsent(values);
              await session.rememberConsent(values);
            }),
          ),
        ),
        GoRoute(
          path: Routes.device,
          builder: (context, _) => DeviceScreen(
            speaker: session.speaker,
            onHasDevice: () => session.advance(
                () => session.onboarding.saveDevice(hasDevice: true)),
            onNoDevice: () => session.advance(
                () => session.onboarding.saveDevice(hasDevice: false)),
            onSkip: () => session.advance(
                () => session.onboarding.skip(Routes.device)),
          ),
        ),
        GoRoute(
          path: Routes.allSet,
          builder: (context, _) => FutureBuilder<({bool contact, bool guardian})>(
            future: session.onboarding.whatIsSetUp(),
            builder: (context, snapshot) {
              final state = snapshot.data ?? (contact: false, guardian: false);
              return AllSetScreen(
                speaker: session.speaker,
                hasEmergencyContact: state.contact,
                hasGuardian: state.guardian,
                onStart: () => session.advance(session.onboarding.finish),
              );
            },
          ),
        ),
        GoRoute(
          path: Routes.home,
          builder: (context, _) => DashboardScreen(
            speaker: session.speaker,
            voice: session.voice,
            consent: session.state.consent,
            onScan: () => appNavigate(context, Routes.scan),
            onAssist: () => appNavigate(context, Routes.assist),
            onSos: () => appNavigate(context, Routes.sos),
            onWhatCanISay: () => appNavigate(context, Routes.whatCanISay),
            onSettings: () => appNavigate(context, Routes.settings),
          ),
        ),
        GoRoute(
          path: Routes.scan,
          builder: (context, _) => ScanScreen(
            speaker: session.prioritySpeaker,
            voice: session.voice,
            destination: session.destination,
            positions: session.destination == null
                ? null
                : const GeolocatorLocationSource().positions(),
            onStopGuidance: () async {
              await session.setDestination(null);
              if (context.mounted) appNavigate(context, Routes.scan);
            },
            onBack: () => appNavigate(context, Routes.home),
          ),
        ),
        GoRoute(
          path: Routes.assist,
          builder: (context, _) => AdminFreeFuture<List<Destination>>(
            load: () => session.places.list(session.state.uid ?? ''),
            builder: (_, places) => SmartAssistanceScreen(
              speaker: session.speaker,
              voice: session.voice,
              places: places,
              onGo: (place) async {
                await session.setDestination(place);
                if (context.mounted) appNavigate(context, Routes.scan);
              },
              onManagePlaces: () => appNavigate(context, Routes.savedPlaces),
              onBack: () => appNavigate(context, Routes.home),
            ),
          ),
        ),
        GoRoute(
          path: Routes.savedPlaces,
          builder: (context, _) => AdminFreeFuture<List<Destination>>(
            load: () => session.places.list(session.state.uid ?? ''),
            builder: (_, places) => SavedPlacesScreen(
              speaker: session.speaker,
              places: places,
              onSaveHere: (kind, label) => _saveHere(session, kind, label),
              onRename: (place, label) async {
                await session.places
                    .save(session.state.uid ?? '', place.copyWith(label: label));
                if (context.mounted) appNavigate(context, Routes.savedPlaces);
              },
              onRemove: (place) async {
                await session.places.remove(session.state.uid ?? '', place.id);
                if (context.mounted) appNavigate(context, Routes.savedPlaces);
              },
              onBack: () => appNavigate(context, Routes.settings),
            ),
          ),
        ),
        GoRoute(
          path: Routes.sos,
          builder: (context, _) => SosFlow(
            engine: session.sos,
            userId: session.state.uid,
            speaker: session.speaker,
            voiceController: session.voice,
            contacts: session.state.contacts,
            guardianCount: session.state.guardianCount,
            onFinished: () => appNavigate(context, Routes.home),
          ),
        ),
        GoRoute(
          path: Routes.settings,
          builder: (context, _) => SettingsScreen(
            speaker: session.speaker,
            contactCount: session.state.contacts.length,
            hasGuardian: session.state.guardianCount > 0,
            onConsent: () => appNavigate(context, Routes.consentCentre),
            onLearned: () => appNavigate(context, Routes.learned),
            onSavedPlaces: () => appNavigate(context, Routes.savedPlaces),
            onDevice: () => appNavigate(context, Routes.device),
            onEmergencyContact: () =>
                appNavigate(context, Routes.emergencyContact),
            onInviteGuardian: () => appNavigate(context, Routes.inviteGuardian),
            onSafetyNotice: () => appNavigate(context, Routes.safety),
            onSignOut: () => appNavigate(context, Routes.signOut),
            onBack: () => appNavigate(context, Routes.home),
          ),
        ),
        GoRoute(
          path: Routes.signOut,
          builder: (context, _) => SignOutScreen(
            speaker: session.speaker,
            // No navigation afterwards: signing out makes the redirect true
            // again, and it sends them to the safety notice and then the
            // welcome screen on its own.
            onSignOut: session.signOut,
            onCancel: () => appNavigate(context, Routes.settings),
          ),
        ),
        GoRoute(
          path: Routes.consentCentre,
          builder: (context, _) => ConsentCentreScreen(
            speaker: session.speaker,
            current: session.state.consent,
            onSave: (values) async {
              await session.onboarding.saveConsent(values);
              await session.rememberConsent(values);
              unawaited(session.refreshProfile());
            },
            onBack: () => appNavigate(context, Routes.settings),
          ),
        ),
        GoRoute(
          path: Routes.learned,
          builder: (context, _) => AdminFreeFuture<List<Place>>(
            load: () => session.history.places(session.state.uid ?? ''),
            builder: (_, places) => LearnedDataScreen(
              speaker: session.speaker,
              places: places,
              offset: DateTime.now().timeZoneOffset,
              onForgetAll: () async {
                await session.history.forgetAll(session.state.uid ?? '');
                if (context.mounted) appNavigate(context, Routes.settings);
              },
              onForgetPlace: (place) async {
                await session.history
                    .forgetPlace(session.state.uid ?? '', place);
                if (context.mounted) appNavigate(context, Routes.learned);
              },
              onBack: () => appNavigate(context, Routes.settings),
            ),
          ),
        ),
        GoRoute(
          path: Routes.whatCanISay,
          builder: (context, _) => WhatCanISayScreen(
            speaker: session.speaker,
            onBack: () => appNavigate(context, Routes.home),
          ),
        ),

        // ---- guardian app (mobile) ----
        GoRoute(
          path: Routes.guardianHome,
          builder: (context, _) => GuardianHomePage(
            guardianId: session.state.uid ?? '',
            repository: session.guardian,
            presenter: session.alerts,
            speaker: session.speaker,
            onEnterCode: () => appNavigate(context, Routes.guardianAccept),
            onSignOut: () => appNavigate(context, Routes.signOut),
          ),
        ),
        GoRoute(
          path: Routes.guardianRegister,
          builder: (context, _) => GuardianRegisterScreen(
            speaker: session.speaker,
            onRegister: (registration) async {
              final failure =
                  await session.guardianOnboarding.register(registration);
              await session.load();
              return failure;
            },
            onSignIn: () => appNavigate(context, Routes.signIn),
          ),
        ),
        GoRoute(
          path: Routes.guardianAccept,
          builder: (context, _) => AcceptInvitationScreen(
            onRedeem: (code) => _redeem(session, code),
            onAccepted: () => appNavigate(context, Routes.guardianHome),
          ),
        ),

        // ---- admin dashboard (web) ----
        _page(Routes.adminRoot, 'Admin', 'Phase 3', 'Overview'),
        GoRoute(
          path: Routes.adminSignIn,
          builder: (_, __) => AdminSignInScreen(
            onSignIn: (email, password) => session.auth.signIn(email, password),
            // Present only when authentication worked and the roster check did
            // not. The screen explains itself instead of silently reappearing.
            signedInAs: session.state.signedIn && !session.state.isAdmin
                ? (session.auth.email ?? 'this account')
                : null,
            signedInUid: session.state.uid,
            onSignOut: () => session.auth.signOut(),
          ),
        ),
        GoRoute(
          path: Routes.adminOverview,
          builder: (context, _) => AdminPage<UsageOverview>(
            route: Routes.adminOverview,
            title: 'Overview',
            subtitle: 'Last 30 days',
            load: session.admin.overview,
            isEmpty: (data) => data.sessions == 0,
            emptyTitle: 'No sessions yet',
            builder: (_, data) => OverviewScreen(overview: data),
            onSelect: (s) => appNavigate(context, s.route),
            onSignOut: session.auth.signOut,
            account: session.auth.email,
          ),
        ),
        GoRoute(
          path: Routes.adminUsers,
          builder: (context, _) => AdminPage<
              ({List<AdminUserRow> users, List<UserInvite> invites})>(
            route: Routes.adminUsers,
            title: 'Users',
            subtitle: 'Visually impaired users, guardians and administrators',
            load: () async {
              final results = await Future.wait([
                session.admin.users(),
                session.admin.pendingInvites(),
              ]);
              return (
                users: results[0] as List<AdminUserRow>,
                invites: results[1] as List<UserInvite>,
              );
            },
            builder: (context, data) => UsersScreen(
              users: data.users,
              invites: data.invites,
              onInvite: () async {
                final request = await showInviteDialog(context);
                if (request == null) return;
                await session.admin.invite(
                  email: request.email,
                  role: request.role,
                  deviceId: request.deviceId,
                  invitedBy: session.state.uid,
                );
                if (context.mounted) appNavigate(context, Routes.adminUsers);
              },
              onWithdraw: (invite) async {
                await session.admin.withdrawInvite(invite.email);
                if (context.mounted) appNavigate(context, Routes.adminUsers);
              },
            ),
            onSelect: (s) => appNavigate(context, s.route),
            onSignOut: session.auth.signOut,
            account: session.auth.email,
          ),
        ),
        GoRoute(
          path: Routes.adminHealth,
          builder: (context, _) => AdminPage<
              ({UsageOverview overview, List<SessionSummary> flagged})>(
            route: Routes.adminHealth,
            title: 'System health',
            subtitle: 'What can be measured without a server',
            load: () async {
              final results = await Future.wait([
                session.admin.overview(),
                session.admin.sessionsNeedingAttention(),
              ]);
              return (
                overview: results[0] as UsageOverview,
                flagged: results[1] as List<SessionSummary>,
              );
            },
            builder: (_, data) => SystemHealthScreen(
              overview: data.overview,
              sessionsNeedingAttention: data.flagged,
            ),
            onSelect: (s) => appNavigate(context, s.route),
            onSignOut: session.auth.signOut,
            account: session.auth.email,
          ),
        ),
        GoRoute(
          path: Routes.adminAccessibility,
          builder: (context, _) => AdminShell(
            current: Routes.adminAccessibility,
            title: 'Accessibility results',
            subtitle: 'Measured, not audited',
            onSelect: (s) => appNavigate(context, s.route),
            onSignOut: session.auth.signOut,
            account: session.auth.email,
            child: const AccessibilityScreen(),
          ),
        ),
      ],
    );
  // A spoken "help" has to end up on the SOS screen. The controller is
  // app-wide and the router is the only thing that can move the user, so it
  // is wired here rather than in a screen.
  session.navigate = router.go;
  return router;
}

GoRoute _page(String path, String title, String phase, String requirement) =>
    GoRoute(
      path: path,
      builder: (_, __) =>
          PendingScreen(title: title, phase: phase, requirement: requirement),
    );


/// Redeems a code as the signed-in guardian.
///
/// Returns null on success, or the sentence to show. Lives here rather than in
/// the screen so the screen stays testable without Firestore.
Future<String?> _redeem(AppSession session, String code) async {
  final guardianId = session.state.uid;
  if (guardianId == null) {
    return 'Sign in first, then enter the code they gave you.';
  }
  final result = await session.pairing.redeem(code, guardianId: guardianId);
  return switch (result) {
    RedeemSucceeded() => null,
    RedeemFailed(:final spoken) => spoken,
  };
}

/// Saves the current position under [kind]. Returns null, or why not.
///
/// Waits longer than the SOS location budget - nobody is in danger here,
/// and a place saved from a cell-tower guess is a Home button that points
/// at the wrong street.
Future<String?> _saveHere(
    AppSession session, DestinationKind kind, String label) async {
  const source = GeolocatorLocationSource();
  final availability = await source.requestPermission();
  if (availability != LocationAvailability.ready) {
    return permissionGuidance(availability);
  }
  final fix = await source.currentFix(timeout: const Duration(seconds: 15));
  if (fix == null) {
    return 'Could not get your position. Try again outdoors, or near a '
        'window.';
  }
  if (fix.accuracyMetres > 100) {
    return 'Your position is only known to about ${fix.accuracyMetres.round()} '
        'metres. Wait a moment and try again.';
  }
  final uid = session.state.uid ?? '';
  final id = destinationIdFor(kind,
      fresh: () => 'place-${DateTime.now().millisecondsSinceEpoch}');
  await session.places.save(
    uid,
    Destination(
      id: id,
      label: label,
      latitude: fix.latitude,
      longitude: fix.longitude,
      kind: kind,
    ),
  );
  return null;
}

/// Extracted so the navigation on success is one named thing rather than an
/// inline closure inside a route table.
void appNavigate(BuildContext context, String location) =>
    GoRouter.of(context).go(location);


/// Shown when a pairing code could not be issued.
///
/// The alternative - showing a made-up code - would send a guardian to type
/// something that was never issued, and fail with no way to tell why.
class _CouldNotIssueCode extends StatelessWidget {
  const _CouldNotIssueCode({required this.speaker, required this.onSkip});

  final Speaker speaker;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => ViScreen(
        speaker: speaker,
        step: 'Step 5 of 7',
        title: 'Could not create an invitation',
        body: const [
          'This usually means there is no connection. You can invite a guardian '
              'later from settings.',
        ],
        actions: [
          ViButton(
            label: 'Continue without a guardian',
            icon: Icons.arrow_forward,
            onPressed: onSkip,
          ),
        ],
      );
}


/// Loads something for a screen in the visually impaired app.
///
/// Named for what it is not: the dashboard's [AdminPage] shows a spinner and a
/// refusal message, which is right for a sighted operator. Here a failure falls
/// through to an empty result instead, because a blind user stuck on a spinner
/// has no way to know that is what they are looking at.
class AdminFreeFuture<T> extends StatelessWidget {
  const AdminFreeFuture({
    super.key,
    required this.load,
    required this.builder,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            // An empty list reads as "nothing learned yet", which is true
            // enough offline and better than a dead end.
            return builder(context, <Never>[] as T);
          }
          return builder(context, data);
        },
      );
}
