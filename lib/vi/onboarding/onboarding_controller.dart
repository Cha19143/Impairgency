import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../app/routes.dart';
import '../../core/profile/impairment.dart';
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
      // Seeded here rather than by [_complete] so the document is written once.
      'onboardingSteps': [Routes.createAccount],
    });
    await store.markStepComplete(Routes.createAccount);
    return null;
  }

  /// Marks [route] finished, on the device and on the account.
  ///
  /// The device's copy is what the router reads, because it has to decide
  /// where to go before anything touches the network. It is the wrong place
  /// for the *only* copy: a user signing in on a second phone, or after a
  /// reinstall, has an empty one, and the router would send them back to step
  /// one to create the account they are already signed in to.
  Future<void> _complete(String route) async {
    await store.markStepComplete(route);
    unawaited(_recordRemotely(route));
  }

  /// Deliberately not awaited by [_complete].
  ///
  /// A Firestore write completes when the *server* acknowledges it, so
  /// awaiting one on a phone with no signal never returns and the step's
  /// screen hangs on a spinner. The SDK queues the write and sends it when the
  /// network comes back; until then the device's copy is the truth, which is
  /// what it is there for.
  Future<void> _recordRemotely(String route) async {
    try {
      await _me?.set(
        {'onboardingSteps': FieldValue.arrayUnion([route])},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Offline, or signed out mid-step. The device's copy still stands.
    }
  }

  /// What this account has already finished, written back to the device.
  ///
  /// Called after signing in. Without it the whole sign-in path is a loop: a
  /// returning user authenticates, the router finds no completed steps on this
  /// device, and sends them to *Create your account* — for the account they
  /// have just signed in to.
  Future<Set<String>> restoreProgress() async {
    // Being signed in at all is proof the account exists, so step one is done.
    // True even when the document cannot be read, which is why it is not
    // inside the try.
    final steps = <String>{Routes.createAccount};
    try {
      final data = (await _me?.get())?.data();
      if (data != null) {
        final recorded = data['onboardingSteps'];
        if (recorded is List) steps.addAll(recorded.whereType<String>());
        steps.addAll(stepsEvidencedBy(data));
      }
    } catch (_) {
      // Offline, or the read was refused. Resuming at step two is a worse
      // answer than the right one and a better answer than step one.
    }
    for (final step in steps) {
      await store.markStepComplete(step);
    }
    return steps;
  }

  /// Steps an account proves it has done by what it holds.
  ///
  /// For accounts written before `onboardingSteps` existed, and as a
  /// cross-check for ones written since. Only steps a field actually settles:
  /// `consent` is written all-false when the account is created, so its
  /// presence proves nothing, a skipped guardian invitation writes nothing,
  /// and the last screen writes nothing at all. Those three are what
  /// `onboardingSteps` is for.
  @visibleForTesting
  static Set<String> stepsEvidencedBy(Map<String, dynamic> data) => {
        if (data['name'] != null) Routes.profile,
        if (data['screenStaysOn'] != null) Routes.preferences,
        if (data['emergencyContact'] != null) Routes.emergencyContact,
        if (data['guardianInvited'] == true) Routes.inviteGuardian,
        if (data['hasDevice'] != null) Routes.device,
      };

  /// Name, age, type of impairment, and the optional number a guardian
  /// can call.
  Future<void> savePersonalInfo(PersonalInfo info) async {
    await _me?.set(info.toJson(), SetOptions(merge: true));
    await _complete(Routes.profile);
  }

  Future<void> savePreference({required bool screenStaysOn}) async {
    await _me?.set({
      'screenStaysOn': screenStaysOn,
      // §1.2 still gets a category for its user table, derived from a question
      // that changes the app rather than one that only labels the person.
      'category': screenStaysOn ? 'low vision' : 'blind',
    }, SetOptions(merge: true));
    await _complete(Routes.preferences);
  }

  Future<void> saveEmergencyContact(String name, String number) async {
    await _me?.set({
      'emergencyContact': {'name': name, 'number': number},
    }, SetOptions(merge: true));
    await _complete(Routes.emergencyContact);
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
    await _complete(Routes.consent);
  }

  Future<void> saveDevice({required bool hasDevice}) async {
    await _me?.set({'hasDevice': hasDevice}, SetOptions(merge: true));
    await _complete(Routes.device);
  }

  /// Marks a step done without doing anything else.
  ///
  /// Skipping has to advance. `cprwire`'s skip left the step incomplete, so a
  /// user who skipped was asked again on every launch. Recorded on the account
  /// as well, or the same user on a new phone would be asked all over again.
  Future<void> skip(String route) => _complete(route);

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
    await _complete(Routes.inviteGuardian);
  }

  Future<void> finish() => _complete(Routes.allSet);
}
