/// Persistence for the handful of facts the router needs before anything is
/// signed in.
///
/// An interface rather than `SharedPreferences` directly so the routing tests
/// can run without a platform channel.
library;

/// The handful of facts the app needs before it can reach the network.
class CachedProfile {
  const CachedProfile({
    this.consent = const {},
    this.contactName,
    this.contactNumber,
    this.guardianCount = 0,
  });

  final Map<String, bool> consent;
  final String? contactName;
  final String? contactNumber;
  final int guardianCount;
}

abstract interface class SessionStore {
  Future<bool> safetyAcknowledged();
  Future<void> acknowledgeSafety();

  /// Read on every launch, before anything touches the network.
  ///
  /// §7 asks emergency features to have fallbacks. Account-first onboarding
  /// means an unregistered phone with no signal is a phone with no SOS - but a
  /// phone that has been set up must still reach its dashboard, with the alarm
  /// and the dialler live, when it cannot reach Firestore. That is what this
  /// cache is for.
  Future<CachedProfile> cachedProfile();

  Future<void> cacheProfile(CachedProfile profile);

  /// Onboarding steps already finished, so setup can resume after a kill.
  Future<Set<String>> completedSteps();
  Future<void> markStepComplete(String route);
}

class InMemorySessionStore implements SessionStore {
  InMemorySessionStore({
    bool acknowledged = false,
    Set<String>? steps,
    CachedProfile? profile,
  })  : _acknowledged = acknowledged,
        _steps = {...?steps},
        _profile = profile ?? const CachedProfile();

  bool _acknowledged;
  final Set<String> _steps;
  CachedProfile _profile;

  @override
  Future<CachedProfile> cachedProfile() async => _profile;

  @override
  Future<void> cacheProfile(CachedProfile profile) async => _profile = profile;

  @override
  Future<bool> safetyAcknowledged() async => _acknowledged;

  @override
  Future<void> acknowledgeSafety() async => _acknowledged = true;

  @override
  Future<Set<String>> completedSteps() async => {..._steps};

  @override
  Future<void> markStepComplete(String route) async => _steps.add(route);
}
