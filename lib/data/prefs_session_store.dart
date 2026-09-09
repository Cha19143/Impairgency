import 'dart:convert';

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
  static const _profileKey = 'cached_profile';

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
  Future<CachedProfile> cachedProfile() async {
    final raw = (await _prefs).getString(_profileKey);
    if (raw == null) return const CachedProfile();
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return CachedProfile(
        role: data['role'] as String?,
        consent: Map<String, bool>.from(data['consent'] as Map? ?? const {}),
        contactName: data['contactName'] as String?,
        contactNumber: data['contactNumber'] as String?,
        guardianCount: (data['guardianCount'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      // A corrupt cache must not stop the app opening. Empty is the safe
      // reading: it understates what is set up rather than overstating it.
      return const CachedProfile();
    }
  }

  @override
  Future<void> cacheProfile(CachedProfile profile) async {
    await (await _prefs).setString(
      _profileKey,
      jsonEncode({
        'role': profile.role,
        'consent': profile.consent,
        'contactName': profile.contactName,
        'contactNumber': profile.contactNumber,
        'guardianCount': profile.guardianCount,
      }),
    );
  }

  @override
  Future<void> markStepComplete(String route) async {
    final prefs = await _prefs;
    final steps = (prefs.getStringList(_stepsKey) ?? const <String>[]).toSet()
      ..add(route);
    await prefs.setStringList(_stepsKey, steps.toList());
  }

  /// Removes the three keys rather than calling `clear()`, which would also
  /// take anything another part of the app has stored under its own name.
  @override
  Future<void> forgetAccount() async {
    final prefs = await _prefs;
    await prefs.remove(_stepsKey);
    await prefs.remove(_profileKey);
    await prefs.remove(_safetyKey);
  }
}
