import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/alerts/alert_presenter.dart';
import '../core/places/place.dart';
import '../core/session_store.dart';
import '../core/speech/speaker.dart';
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
import '../data/geolocator_location_source.dart';
import '../data/local_alert_presenter.dart';
import '../data/pairing_repository.dart';
import '../data/location_history_repository.dart';
import '../data/sos_engine.dart';
import '../guardian/screens/accept_invitation_screen.dart';
import '../shared/widgets/pending_screen.dart';
import '../vi/onboarding/all_set_screen.dart';
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
import '../vi/widgets/vi_button.dart';
import '../vi/widgets/vi_screen.dart';
import 'routes.dart';

/// Live session, fed by FirebaseAuth once `flutterfire configure` has been run
/// against the new project. Until then it reports signed out, which is the
/// correct default: the guard fails closed.
class AppSession extends ChangeNotifier {
  AppSession({SessionStore? store, Speaker? speaker, PairingRepository? pairing})
      : store = store ?? InMemorySessionStore(),
        speaker = speaker ?? const SilentSpeaker(),
        _pairing = pairing;

  final SessionStore store;
  final Speaker speaker;

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
      update(SessionState(
        uid: user.uid,
        consent: _state.consent,
        contactName: _state.contactName,
        contactNumber: _state.contactNumber,
        guardianCount: _state.guardianCount,
        signedIn: true,
        isAdmin: isAdmin,
        isGuardian: _state.isGuardian,
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
      isGuardian: _state.isGuardian,
      safetyAcknowledged: await store.safetyAcknowledged(),
      completedSteps: await store.completedSteps(),
      consent: profile.consent,
      contactName: profile.contactName,
      contactNumber: profile.contactNumber,
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
      final contact = data['emergencyContact'] as Map<String, dynamic>?;
      await store.cacheProfile(CachedProfile(
        consent: Map<String, bool>.from(data['consent'] as Map? ?? const {}),
        contactName: contact?['name'] as String?,
        contactNumber: contact?['number'] as String?,
        guardianCount: (data['guardianCount'] as num?)?.toInt() ?? 0,
      ));
      await load();
    } catch (_) {
      // Offline. The cache is what the app runs on until the network returns.
    }
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
  /// The store is cleared *before* Firebase is told, so that there is no
  /// moment where the app is signed out and the previous account's completed
  /// steps and cached emergency contact are still on screen.
  Future<void> signOut() async {
    await store.forgetAccount();
    await auth.signOut();
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

GoRouter createRouter(AppSession session) => GoRouter(
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
            onCreateAccount: () =>
                appNavigate(context, Routes.createAccount),
            onSignIn: () => appNavigate(context, Routes.signIn),
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
            onCreateAccount: () => appNavigate(context, Routes.createAccount),
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
            onSave: (name, number) => session.advance(() =>
                session.onboarding.saveEmergencyContact(name, number)),
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
            onContinue: (values) =>
                session.advance(() => session.onboarding.saveConsent(values)),
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
            consent: session.state.consent,
            onScan: () => appNavigate(context, Routes.scan),
            onAssist: () => appNavigate(context, Routes.home),
            onSos: () => appNavigate(context, Routes.sos),
            onWhatCanISay: () => appNavigate(context, Routes.whatCanISay),
            onSettings: () => appNavigate(context, Routes.settings),
          ),
        ),
        GoRoute(
          path: Routes.scan,
          builder: (context, _) => ScanScreen(
            speaker: session.speaker,
            onBack: () => appNavigate(context, Routes.home),
          ),
        ),
        GoRoute(
          path: Routes.sos,
          builder: (context, _) => SosFlow(
            engine: session.sos,
            userId: session.state.uid ?? 'unknown',
            speaker: session.speaker,
            contactName: session.state.contactName,
            contactNumber: session.state.contactNumber,
            guardianCount: session.state.guardianCount,
            onFinished: () => appNavigate(context, Routes.home),
          ),
        ),
        GoRoute(
          path: Routes.settings,
          builder: (context, _) => SettingsScreen(
            speaker: session.speaker,
            hasContact: session.state.contactNumber != null,
            hasGuardian: session.state.guardianCount > 0,
            onConsent: () => appNavigate(context, Routes.consentCentre),
            onLearned: () => appNavigate(context, Routes.learned),
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
              await session.refreshProfile();
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
        _page(Routes.guardianHome, 'Guardian', 'Phase 1', '§3.1, §3.2'),
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
        step: 'Step 4 of 6',
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
