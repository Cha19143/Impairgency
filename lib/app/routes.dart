/// Route paths and the redirect rule, kept free of Flutter so the rule itself
/// can be unit tested. `router.dart` wires this to go_router.
library;

abstract final class Routes {
  /// Debug-only proving ground for a real GPS fix and a real notification.
  /// Registered only in debug builds - see router.dart.
  static const debug = '/debug';

  /// The limitation notice required by §7. Before everything on mobile, and
  /// reachable again afterwards.
  static const safety = '/safety';

  // Visually impaired user app (mobile)
  static const welcome = '/';

  /// The way back in for an account that already exists. Not part of
  /// [onboardingFlow]: signing in is not a step of setting up, it is the
  /// alternative to it.
  static const signIn = '/sign-in';

  /// Also not a step: the reset link is used *at* sign-in, not during setup.
  static const forgotPassword = '/forgot-password';

  /// Which app the new account is for. Before [createAccount], and not a
  /// step of it: a guardian who chose the other door never sees the flow.
  static const chooseRole = '/onboarding/role';
  static const createAccount = '/onboarding/account';

  /// Name, age, type of impairment - and a number a guardian can call.
  static const profile = '/onboarding/profile';
  static const preferences = '/onboarding/preferences';
  static const emergencyContact = '/onboarding/contact';
  static const inviteGuardian = '/onboarding/guardian';
  static const consent = '/onboarding/consent';
  static const device = '/onboarding/device';
  static const allSet = '/onboarding/done';
  static const home = '/home';
  static const scan = '/scan';
  static const sos = '/sos';
  static const whatCanISay = '/what-can-i-say';
  static const settings = '/settings';
  static const consentCentre = '/settings/consent';
  static const learned = '/settings/learned';
  static const signOut = '/settings/sign-out';

  // Guardian app (mobile)
  static const guardianHome = '/guardian';
  static const guardianAccept = '/guardian/accept';

  /// The guardian's own door in. Reachable signed out, like [createAccount].
  static const guardianRegister = '/guardian/register';

  // Admin dashboard (web)
  static const adminRoot = '/admin';
  static const adminSignIn = '/admin/sign-in';
  static const adminOverview = '/admin/overview';
  static const adminUsers = '/admin/users';
  static const adminSessions = '/admin/sessions';
  static const adminHealth = '/admin/health';
  static const adminAccessibility = '/admin/accessibility';

  /// Ordered onboarding steps. Setup resumes at the first incomplete one - a
  /// blind user restarting from scratch after a crash would be punishing.
  static const onboardingFlow = <String>[
    createAccount,
    profile,
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
    this.consent = const {},
    this.contactName,
    this.contactNumber,
    this.guardianCount = 0,
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

  /// What the user has agreed to, read from their user document. Shown on the
  /// dashboard so consent is visible without opening a settings screen.
  final Map<String, bool> consent;

  /// The emergency contact, so SOS does not have to fetch it mid-emergency.
  final String? contactName;
  final String? contactNumber;

  /// How many guardians are paired. Zero means the SOS receipt says so rather
  /// than reporting a failure that was never attempted.
  final int guardianCount;

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

/// The screens that exist for someone without an account yet, or without one
/// on this device: the two doors and the setup behind them.
///
/// Sign-in belongs here for both of the reasons this function is consulted. It
/// has to be reachable while signed out, and it has to be left behind once
/// setup is done — a signed-in user who lands on it would otherwise be looking
/// at a form for the account they are already using.
bool _isSignedOutRoute(String location) =>
    location.startsWith('/onboarding') ||
    location == Routes.welcome ||
    location == Routes.signIn ||
    location == Routes.forgotPassword ||
    location == Routes.guardianRegister;

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
  // The debug screen is registered only in debug builds, so if the route
  // exists at all it is meant to be reachable.
  if (location == Routes.debug) return null;

  if (isWeb) {
    if (!_isAdminRoute(location)) return Routes.adminRoot;
    if (!session.signedIn) {
      return location == Routes.adminSignIn ? null : Routes.adminSignIn;
    }
    // Authenticated but not on the roster. Staying is correct - the sign-in
    // screen renders a "signed in, but not an administrator" state that names
    // the account and prints the document that would grant it - but say so with
    // null rather than a redirect to the current location, which is a no-op
    // dressed up as a decision.
    if (!session.isAdmin) {
      return location == Routes.adminSignIn ? null : Routes.adminSignIn;
    }

    // Signed in, and on the roster. The sign-in page has to be left as well as
    // the bare /admin root: returning null here means "stay", and go_router
    // treats a redirect to the current location as a no-op — so a correct
    // password redisplayed the login form and nothing appeared to happen.
    //
    // The same shape of bug as the safety notice: a guard that is right about
    // permission and silent about where to go next.
    if (location == Routes.adminRoot || location == Routes.adminSignIn) {
      return Routes.adminOverview;
    }
    return null;
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
    return _isSignedOutRoute(location) ? null : Routes.welcome;
  }

  if (session.isGuardian) {
    // Signing out lives under the visually impaired app's settings path,
    // but a guardian has to be able to leave too.
    if (location == Routes.signOut) return null;
    return _isGuardianRoute(location) ? null : Routes.guardianHome;
  }

  if (!session.setupComplete) {
    final next = session.resumeAt;
    return location == next ? null : next;
  }

  // Setup is done; onboarding is behind them.
  if (_isSignedOutRoute(location)) return Routes.home;
  return null;
}
