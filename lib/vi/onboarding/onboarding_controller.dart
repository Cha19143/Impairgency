import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/routes.dart';
import '../../core/session_store.dart';
import '../../data/auth_service.dart';
import '../../data/pairing_repository.dart';

/// What each onboarding step does when it finishes.
///
/// Kept out of the screens so they stay testable without Firebase, and out of
/// the router so the route table stays readable.
class OnboardingController {
  OnboardingController({
    required this.auth,
    required this.store,
    required this.pairing,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final AuthService auth;
  final SessionStore store;
  final PairingRepository pairing;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>>? get _me {
    final uid = auth.uid;
    return uid == null ? null : _db.collection('users').doc(uid);
  }

  /// Creates the account and its user document.
  ///
  /// Returns null on success, or a sentence to say and show.
  Future<String?> createAccount(String email, String password) async {
    final failure = await auth.createAccount(email, password);
    if (failure != null) return failure;

    final uid = auth.uid;
    if (uid == null) return 'The account was created but could not be opened.';

    await _db.collection('users').doc(uid).set({
      'uid': uid,
      'email': email.trim(),
      'role': 'vi',
      // Every consent starts false. The rules read this map, so an absent key
      // and a false one must mean the same thing - withheld.
      'consent': {
        'location': false,
        'history': false,
        'recording': false,
        'faces': false,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
    await store.markStepComplete(Routes.createAccount);
    return null;
  }

  Future<void> savePreference({required bool screenStaysOn}) async {
    await _me?.set({
      'screenStaysOn': screenStaysOn,
      // §1.2 still gets a category for its user table, derived from a question
      // that changes the app rather than one that only labels the person.
      'category': screenStaysOn ? 'low vision' : 'blind',
    }, SetOptions(merge: true));
    await store.markStepComplete(Routes.preferences);
  }

  Future<void> saveEmergencyContact(String name, String number) async {
    await _me?.set({
      'emergencyContact': {'name': name, 'number': number},
    }, SetOptions(merge: true));
    await store.markStepComplete(Routes.emergencyContact);
  }

  /// A code for the guardian to redeem, or null if it could not be issued.
  Future<String?> issueGuardianCode() async {
    final uid = auth.uid;
    if (uid == null) return null;
    try {
      return await pairing.issueCode(uid);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveConsent(Map<String, bool> values) async {
    await _me?.set({'consent': values}, SetOptions(merge: true));
    await store.markStepComplete(Routes.consent);
  }

  Future<void> saveDevice({required bool hasDevice}) async {
    await _me?.set({'hasDevice': hasDevice}, SetOptions(merge: true));
    await store.markStepComplete(Routes.device);
  }

  /// Marks a step done without doing anything else.
  ///
  /// Skipping has to advance. `cprwire`'s skip left the step incomplete, so a
  /// user who skipped was asked again on every launch.
  Future<void> skip(String route) => store.markStepComplete(route);

  /// What [AllSetScreen] tells the user they actually have.
  Future<({bool contact, bool guardian})> whatIsSetUp() async {
    final snapshot = await _me?.get();
    final data = snapshot?.data();
    return (
      contact: data?['emergencyContact'] != null,
      guardian: data?['guardianInvited'] == true,
    );
  }

  Future<void> markGuardianInvited() async {
    await _me?.set({'guardianInvited': true}, SetOptions(merge: true));
    await store.markStepComplete(Routes.inviteGuardian);
  }

  Future<void> finish() => store.markStepComplete(Routes.allSet);
}
