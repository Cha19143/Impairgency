import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/session_store.dart';
import '../core/speech/speaker.dart';
import '../data/pairing_repository.dart';
import '../guardian/screens/accept_invitation_screen.dart';
import '../shared/widgets/pending_screen.dart';
import '../vi/screens/safety_notice_screen.dart';
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

  SessionState _state = const SessionState();
  SessionState get state => _state;

  /// Reads what was persisted before the first frame decides where to go.
  Future<void> load() async {
    update(SessionState(
      signedIn: _state.signedIn,
      isAdmin: _state.isAdmin,
      isGuardian: _state.isGuardian,
      safetyAcknowledged: await store.safetyAcknowledged(),
      completedSteps: await store.completedSteps(),
    ));
  }

  void update(SessionState next) {
    _state = next;
    notifyListeners();
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

GoRouter createRouter(AppSession session) => GoRouter(
      initialLocation: kIsWeb ? Routes.adminRoot : Routes.welcome,
      refreshListenable: session,
      redirect: (context, state) => resolveRedirect(
        isWeb: kIsWeb,
        location: state.matchedLocation,
        session: session.state,
      ),
      routes: [
        GoRoute(
          path: Routes.safety,
          builder: (_, __) => SafetyNoticeScreen(
            speaker: session.speaker,
            alreadyAcknowledged: session.state.safetyAcknowledged,
            onAcknowledge: session.acknowledgeSafety,
          ),
        ),

        // ---- visually impaired user app (mobile) ----
        _page(Routes.welcome, 'Welcome', 'Phase 4', '§4'),
        _page(Routes.createAccount, 'Create account', 'Phase 4', '§4'),
        _page(Routes.preferences, "How you'll use it", 'Phase 4', '§4'),
        _page(Routes.emergencyContact, 'Emergency contact', 'Phase 4', '§2.A.5'),
        _page(Routes.inviteGuardian, 'Invite a guardian', 'Phase 1', '§3'),
        _page(Routes.consent, 'Consent', 'Phase 4', '§7'),
        _page(Routes.device, 'Device', 'Phase 4', '§5'),
        _page(Routes.allSet, 'All set', 'Phase 4', '§4'),
        _page(Routes.home, 'Dashboard', 'Phase 4', '§2.C'),

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
        _page(Routes.adminSignIn, 'Admin sign-in', 'Phase 3', '§1.2'),
        _page(Routes.adminOverview, 'Overview', 'Phase 3', '§1.3, §1.4'),
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
