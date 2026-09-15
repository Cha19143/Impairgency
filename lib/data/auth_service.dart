import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Why an account could not be made: the sentence to say, and Firebase's own
/// code, so a caller can tell "that email already has an account" from every
/// other refusal without matching on the words.
class AuthFailure {
  const AuthFailure(this.message, {this.code});

  final String message;
  final String? code;

  bool get emailInUse => code == 'email-already-in-use';
}

/// The signed-in account as the router needs it: who, and whether they have
/// to confirm their email first. A plain class so the auth listener can be
/// driven by a test, which cannot construct a Firebase `User`.
class AuthAccount {
  const AuthAccount({
    required this.uid,
    this.email,
    this.emailVerified = false,
    this.createdAt,
  });

  final String uid;
  final String? email;
  final bool emailVerified;
  final DateTime? createdAt;
}

/// What checking the verification link came back with.
enum VerificationCheck { verified, notYet, failed }

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

  /// [changes], as the parts the router reads.
  Stream<AuthAccount?> get accounts => _auth.authStateChanges().map(
        (user) => user == null
            ? null
            : AuthAccount(
                uid: user.uid,
                email: user.email,
                emailVerified: user.emailVerified,
                createdAt: user.metadata.creationTime,
              ),
      );

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

  /// Whether the verification email for the account made by
  /// [createAccount] actually left. Null until one has been tried.
  bool? verificationSent;

  /// Returns null on success, or why not.
  ///
  /// The verification email is sent separately and its failure is not this
  /// method's failure. It used to be: a `too-many-requests` on the email after
  /// the account already existed came back as "account not created", the
  /// guardian flow put the cached role back, and the next launch sent a new
  /// guardian into the visually impaired app. The account exists; a missing
  /// email is something the verify screen can send again.
  Future<AuthFailure?> createAccount(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      verificationSent = null;
      try {
        await credential.user?.sendEmailVerification();
        verificationSent = true;
      } catch (e) {
        verificationSent = false;
        debugPrint('Verification email not sent: $e');
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return AuthFailure(describeAuthError(e.code), code: e.code);
    } catch (_) {
      return const AuthFailure(
          'Something went wrong. Check your connection and try again.');
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

  /// Sends the link again. Returns null when it has gone, or why not.
  Future<String?> sendVerification() async {
    final user = _auth.currentUser;
    if (user == null) return 'You are signed out. Sign in again first.';
    try {
      await user.sendEmailVerification();
      verificationSent = true;
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('Verification email not sent: ${e.code}');
      return switch (e.code) {
        'too-many-requests' => 'Too many links have been sent. Wait a few '
            'minutes, then try again.',
        'network-request-failed' =>
          'No connection. Check your network and try again.',
        _ => 'The link could not be sent. Try again in a minute.',
      };
    } catch (e) {
      debugPrint('Verification email not sent: $e');
      return 'The link could not be sent. Check your connection and try '
          'again.';
    }
  }

  /// Re-reads the account, so a user who has just clicked the link in their
  /// email is seen as verified without signing out and back in.
  Future<bool> refreshVerification() async {
    await _auth.currentUser?.reload();
    return isEmailVerified;
  }

  /// Whether the link has been followed, asked of the server.
  ///
  /// A fresh ID token as well once it has, so anything that reads the
  /// token's `email_verified` claim sees the change without a sign-out.
  Future<VerificationCheck> checkVerification() async {
    final user = _auth.currentUser;
    if (user == null) return VerificationCheck.failed;
    try {
      await user.reload();
      final fresh = _auth.currentUser;
      if (fresh == null || !fresh.emailVerified) return VerificationCheck.notYet;
      await fresh.getIdToken(true);
      return VerificationCheck.verified;
    } catch (e) {
      debugPrint('Could not check verification: $e');
      return VerificationCheck.failed;
    }
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
