/// Route paths and the redirect rule, kept free of Flutter so the rule itself
/// can be unit tested. `router.dart` wires this to go_router.
library;

abstract final class Routes {
  /// The limitation notice required by §7. Before everything on mobile, and
  /// reachable again afterwards.
  static const safety = '/safety';

  // Visually impaired user app (mobile)
  static const welcome = '/';
  static const createAccount = '/onboarding/account';
  static const preferences = '/onboarding/preferences';
  static const emergencyContact = '/onboarding/contact';
  static const inviteGuardian = '/onboarding/guardian';
  static const consent = '/onboarding/consent';
  static const device = '/onboarding/device';
  static const allSet = '/onboarding/done';
  static const home = '/home';

  // Guardian app (mobile)
  static const guardianHome = '/guardian';
  static const guardianAccept = '/guardian/accept';

  // Admin dashboard (web)
  static const adminRoot = '/admin';
  static const adminSignIn = '/admin/sign-in';
  static const adminOverview = '/admin/overview';

  /// Ordered onboarding steps. Setup resumes at the first incomplete one - a
  /// blind user restarting from scratch after a crash would be punishing.
  static const onboardingFlow = <String>[
    createAccount,
    preferences,
    emergencyContact,
    inviteGuardian,
    consent,
    device,
    allSet,
  ];
}

/// Everything the redirect rule needs to know.
class SessionState {
  const SessionState({
    this.uid,
    this.signedIn = false,
    this.isAdmin = false,
    this.isGuardian = false,
    this.safetyAcknowledged = false,
    this.completedSteps = const <String>{},
  });

  /// The signed-in account, or null. Present so screens that write on the
  /// user's behalf do not have to reach for FirebaseAuth themselves.
  final String? uid;

  final bool signedIn;
  final bool isAdmin;
  final bool isGuardian;

  /// Whether the §7 limitation notice has been seen and acknowledged.
  /// Defaults to false, so a fresh install always hears it.
  final bool safetyAcknowledged;

  final Set<String> completedSteps;

  bool get setupComplete =>
      Routes.onboardingFlow.every(completedSteps.contains);

  /// The first onboarding step not yet finished.
  String get resumeAt => Routes.onboardingFlow.firstWhere(
        (step) => !completedSteps.contains(step),
        orElse: () => Routes.home,
      );
}

bool _isAdminRoute(String location) => location.startsWith(Routes.adminRoot);
bool _isGuardianRoute(String location) =>
    location.startsWith(Routes.guardianHome);
bool _isOnboardingRoute(String location) =>
    location.startsWith('/onboarding') || location == Routes.welcome;

/// Where the app should send this request, or null to let it through.
///
/// Two jobs, and the old project did neither:
///
///  1. **Platform split.** The requirements document names the admin dashboard
///     as a web application. On web the app is the dashboard and nothing else;
///     on mobile it is the user and guardian apps and nothing else. One
///     codebase, two entry points, one `flutter build web` that ships only the
///     dashboard.
///  2. **Auth guard.** `/admin/*` was previously a plain route with no check.
///     On mobile that needed a rooted device to reach. On web it is a URL.
String? resolveRedirect({
  required bool isWeb,
  required String location,
  required SessionState session,
}) {
  if (isWeb) {
    if (!_isAdminRoute(location)) return Routes.adminRoot;
    if (!session.signedIn) {
      return location == Routes.adminSignIn ? null : Routes.adminSignIn;
    }
    if (!session.isAdmin) return Routes.adminSignIn;
    return location == Routes.adminRoot ? Routes.adminOverview : null;
  }

  // Mobile: the dashboard is not reachable, signed in or not.
  if (_isAdminRoute(location)) return Routes.welcome;

  // The safety notice comes before everything, including sign-in. Someone who
  // opens this app for the first time hears what it cannot do before they hear
  // what it can.
  if (!session.safetyAcknowledged) {
    return location == Routes.safety ? null : Routes.safety;
  }
  // Still reachable once acknowledged - the notice says so, so the router has
  // to honour it.
  if (location == Routes.safety) return null;

  if (!session.signedIn) {
    return _isOnboardingRoute(location) ? null : Routes.welcome;
  }

  if (session.isGuardian) {
    return _isGuardianRoute(location) ? null : Routes.guardianHome;
  }

  if (!session.setupComplete) {
    final next = session.resumeAt;
    return location == next ? null : next;
  }

  // Setup is done; onboarding is behind them.
  if (_isOnboardingRoute(location)) return Routes.home;
  return null;
}
