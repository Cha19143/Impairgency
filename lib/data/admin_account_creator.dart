import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../app/emulator.dart';
import '../app/routes.dart';
import '../core/admin/admin_user.dart';
import 'auth_service.dart' show describeAuthError;

/// What adding an account came to.
sealed class AccountCreation {
  const AccountCreation();
}

class AccountCreated extends AccountCreation {
  const AccountCreated(this.uid);
  final String uid;
}

class AccountNotCreated extends AccountCreation {
  const AccountNotCreated(this.message, {this.code});
  final String message;
  final String? code;
}

/// Makes an account from the dashboard without signing the administrator out.
///
/// Firebase's client SDK signs in whoever it has just created. On the default
/// app that is a sign-out for the administrator - the dashboard's own auth
/// listener would see a stranger and send the page to sign-in - which is the
/// reason the dashboard only sent invitations until now. A second, named
/// Firebase app keeps its own signed-in user: the account is made there, its
/// document written there *as that new user* (so the rule that lets people
/// create their own profile is the one that applies), and that app signs out.
///
/// Nobody chooses a password. The account gets a long random one that is
/// never shown or stored, and the person is sent Firebase's own link to choose
/// theirs - the same email "Forgot your password?" sends.
class AdminAccountCreator {
  static const String _appName = 'account-admin';

  bool _wired = false;

  Future<FirebaseApp> _app() async {
    for (final app in Firebase.apps) {
      if (app.name == _appName) return app;
    }
    // Kept for the life of the page rather than deleted after each use:
    // FirebaseAuth caches its instance by app name, and one tied to a deleted
    // app answers every call with an error.
    return Firebase.initializeApp(
        name: _appName, options: Firebase.app().options);
  }

  Future<AccountCreation> create(NewAccount account) async {
    final FirebaseAuth auth;
    final FirebaseFirestore db;
    try {
      final app = await _app();
      auth = FirebaseAuth.instanceFor(app: app);
      db = FirebaseFirestore.instanceFor(app: app);
      if (!_wired) {
        _wired = true;
        if (kUseEmulator) {
          await auth.useAuthEmulator(kEmulatorHost, kAuthEmulatorPort);
          db.useFirestoreEmulator(kEmulatorHost, kFirestoreEmulatorPort);
        }
        // Nothing about this second sign-in should outlive the call, or share
        // storage with the administrator's own.
        if (kIsWeb) await auth.setPersistence(Persistence.NONE);
      }
    } catch (e) {
      debugPrint('Account creator unavailable: $e');
      return const AccountNotCreated(
          'Accounts cannot be added from this browser right now. Try again, '
          'or send an invitation instead.');
    }

    final email = account.email.trim();
    final String uid;
    try {
      final credential = await auth.createUserWithEmailAndPassword(
          email: email, password: _unusedPassword());
      uid = credential.user!.uid;
    } on FirebaseAuthException catch (e) {
      return AccountNotCreated(
        e.code == 'email-already-in-use'
            ? 'That email already has an account.'
            : describeAuthError(e.code),
        code: e.code,
      );
    } catch (e) {
      debugPrint('Account not created: $e');
      return const AccountNotCreated(
          'The account could not be made. Check the connection and try again.');
    }

    try {
      await db.collection('users').doc(uid).set({
        ...account.toUserDocument(uid),
        'createdAt': FieldValue.serverTimestamp(),
        if (account.role == 'vi')
          'onboardingSteps': [
            Routes.createAccount,
            if (account.profileComplete) Routes.profile,
          ],
      });
      await auth.sendPasswordResetEmail(email: email);
      return AccountCreated(uid);
    } catch (e) {
      debugPrint('Account made but not finished: $e');
      return AccountNotCreated(
          'The sign-in for $email was made, but its details or its email '
          'could not be sent. Remove it and add it again, or ask them to use '
          '"Forgot your password?" in the app.');
    } finally {
      try {
        await auth.signOut();
      } catch (_) {
        // Already signed out.
      }
    }
  }

  /// Long, random, and thrown away. The account's owner replaces it with the
  /// link in their email; nobody else ever has it.
  static String _unusedPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
        '23456789-_!@#%';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
