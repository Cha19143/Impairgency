import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/pending_screen.dart';
import 'routes.dart';

/// Live session, fed by FirebaseAuth once `flutterfire configure` has been run
/// against the new project. Until then it reports signed out, which is the
/// correct default: the guard fails closed.
class AppSession extends ChangeNotifier {
  SessionState _state = const SessionState();
  SessionState get state => _state;

  void update(SessionState next) {
    _state = next;
    notifyListeners();
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
        _page(Routes.guardianAccept, 'Accept invitation', 'Phase 1', '§3'),

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
