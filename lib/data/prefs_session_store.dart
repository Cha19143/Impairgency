import 'package:shared_preferences/shared_preferences.dart';

import '../core/session_store.dart';

/// [SessionStore] backed by the device.
///
/// Deliberately local rather than Firestore: the safety notice has to work on a
/// first run with no account and no network, which is exactly the situation it
/// was written for.
class PrefsSessionStore implements SessionStore {
  static const _safetyKey = 'safety_notice_acknowledged';
  static const _stepsKey = 'onboarding_completed_steps';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<bool> safetyAcknowledged() async =>
      (await _prefs).getBool(_safetyKey) ?? false;

  @override
  Future<void> acknowledgeSafety() async =>
      (await _prefs).setBool(_safetyKey, true);

  @override
  Future<Set<String>> completedSteps() async =>
      ((await _prefs).getStringList(_stepsKey) ?? const <String>[]).toSet();

  @override
  Future<void> markStepComplete(String route) async {
    final prefs = await _prefs;
    final steps = (prefs.getStringList(_stepsKey) ?? const <String>[]).toSet()
      ..add(route);
    await prefs.setStringList(_stepsKey, steps.toList());
  }
}
