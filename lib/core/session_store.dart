/// Persistence for the handful of facts the router needs before anything is
/// signed in.
///
/// An interface rather than `SharedPreferences` directly so the routing tests
/// can run without a platform channel.
library;

abstract interface class SessionStore {
  Future<bool> safetyAcknowledged();
  Future<void> acknowledgeSafety();

  /// Onboarding steps already finished, so setup can resume after a kill.
  Future<Set<String>> completedSteps();
  Future<void> markStepComplete(String route);
}

class InMemorySessionStore implements SessionStore {
  InMemorySessionStore({bool acknowledged = false, Set<String>? steps})
      : _acknowledged = acknowledged,
        _steps = {...?steps};

  bool _acknowledged;
  final Set<String> _steps;

  @override
  Future<bool> safetyAcknowledged() async => _acknowledged;

  @override
  Future<void> acknowledgeSafety() async => _acknowledged = true;

  @override
  Future<Set<String>> completedSteps() async => {..._steps};

  @override
  Future<void> markStepComplete(String route) async => _steps.add(route);
}
