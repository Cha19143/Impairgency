import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// Sign-in, and the two facts the router needs from it.
///
/// Email verification is Firebase Auth's own. cprwire stored six-digit codes in
/// an `otp_verification` collection and mailed them with EmailJS; a database of
/// live login codes is an account takeover waiting to be found, and making it
/// safe needed a Cloud Function. `sendEmailVerification` is free, needs no
/// server, and stores nothing.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  String? get uid => _auth.currentUser?.uid;
  String? get email => _auth.currentUser?.email;
  bool get isSignedIn => _auth.currentUser != null;
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  Stream<User?> get changes => _auth.authStateChanges();

  /// Returns null on success, or a sentence to show.
  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return describeAuthError(e.code);
    } catch (_) {
      return 'Something went wrong. Check your connection and try again.';
    }
  }

  Future<String?> createAccount(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      await credential.user?.sendEmailVerification();
      return null;
    } on FirebaseAuthException catch (e) {
      return describeAuthError(e.code);
    } catch (_) {
      return 'Something went wrong. Check your connection and try again.';
    }
  }

  /// Sends Firebase's own reset link.
  ///
  /// Returns null when it is on its way - including when there is no such
  /// account. Firebase itself answers that way once email enumeration
  /// protection is on, and the screen says the same sentence either way, so
  /// nobody can use this form to learn which addresses are registered.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return null;
      return describeAuthError(e.code);
    } catch (_) {
      return 'Something went wrong. Check your connection and try again.';
    }
  }

  Future<void> resendVerification() =>
      _auth.currentUser?.sendEmailVerification() ?? Future.value();

  /// Re-reads the account, so a user who has just clicked the link in their
  /// email is seen as verified without signing out and back in.
  Future<bool> refreshVerification() async {
    await _auth.currentUser?.reload();
    return isEmailVerified;
  }

  Future<void> signOut() => _auth.signOut();
}

/// Firebase's error codes, said in words.
///
/// Firebase returns things like `invalid-credential`, which is accurate and
/// tells nobody what to do next.
String describeAuthError(String code) => switch (code) {
      'invalid-email' => 'That does not look like an email address.',
      'user-disabled' => 'This account has been turned off. Contact an administrator.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'That email and password do not match an account.',
      'email-already-in-use' =>
        'There is already an account with that email. Try signing in instead.',
      'weak-password' =>
        'That password is too easy to guess. Use at least eight characters.',
      'too-many-requests' =>
        'Too many attempts. Wait a few minutes and try again.',
      'network-request-failed' =>
        'No connection. Check your network and try again.',
      _ => 'Sign-in failed. Please try again.',
    };
