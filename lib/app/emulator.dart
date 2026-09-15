/// Pointing the app at the local Firebase emulators instead of the live
/// project.
///
///     flutter run -d chrome --dart-define=USE_EMULATOR=true
///
/// A compile-time constant, so a release build cannot carry it in by accident -
/// the same shape as the START override in app/router.dart.
///
/// The project id is overridden along with the hosts. The Firestore emulator
/// only enforces the ruleset it was started with for the project it was started
/// as, so matching `demo-impairgency` - the id tool/test_rules.sh already uses -
/// is what makes the browser tests run against the real firestore.rules rather
/// than against an unguarded namespace.
///
/// Shared, rather than private to main.dart, because the dashboard's second
/// Firebase app - the one that creates accounts - has to be pointed at the
/// same emulators as the first.
library;

const bool kUseEmulator = bool.fromEnvironment('USE_EMULATOR');
const String kEmulatorProjectId = 'demo-impairgency';
const String kEmulatorHost = 'localhost';
const int kAuthEmulatorPort = 9099;
const int kFirestoreEmulatorPort = 8080;
