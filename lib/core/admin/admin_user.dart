/// The accounts the web dashboard manages, as plain values.
///
/// Flutter-free and Firestore-free, so the filters and the dialogs built on
/// them are tested without either.
library;

import 'dart:async';

import '../auth/email_address.dart';
import '../profile/impairment.dart';

/// Whether the signed-in account is on the admin roster, as far as the read
/// could tell.
///
/// Three answers, because a read can fail without saying no. The check used to
/// return false for any failure, once, at sign-in: an administrator whose first
/// read met a cold connection was told they were not one, and every sidebar
/// click after that bounced back to the sign-in page for the rest of the
/// session.
enum RosterCheck { admin, notAdmin, unknown }

/// Why a dashboard read failed, in the terms the page explains it in.
enum AdminLoadFailure {
  /// The rules said no - usually an account that is not on the roster.
  refused,

  /// The database was not reached, or did not answer in time.
  unreachable,

  /// Anything else: a missing index, a bug. Blamed on neither of the above.
  other,
}

/// Sorts an error from a dashboard read.
///
/// Firebase errors are recognised by the code they print -
/// `[cloud_firestore/permission-denied] ...` - rather than by type, so this
/// file stays free of the Firebase packages.
AdminLoadFailure describeFailure(Object error) {
  if (error is TimeoutException) return AdminLoadFailure.unreachable;
  final code = RegExp(r'\[[\w.-]+/([\w-]+)\]').firstMatch('$error')?.group(1);
  return switch (code) {
    'permission-denied' || 'unauthenticated' => AdminLoadFailure.refused,
    'unavailable' ||
    'deadline-exceeded' ||
    'network-request-failed' =>
      AdminLoadFailure.unreachable,
    _ => AdminLoadFailure.other,
  };
}

/// An account an administrator makes from the dashboard.
///
/// No password: the person is emailed a link to choose their own, and the
/// account never has one anybody else knows.
class NewAccount {
  const NewAccount({
    required this.email,
    required this.name,
    required this.role,
    this.impairment,
    this.age,
    this.phone,
  });

  final String email;
  final String name;

  /// 'vi' or 'guardian'. Administrators are granted in the Firebase console.
  final String role;

  final ImpairmentType? impairment;
  final int? age;
  final String? phone;

  /// Whether "About you" is already answered, so a visually impaired user is
  /// not asked it again when they first sign in.
  bool get profileComplete =>
      role == 'vi' && name.trim().isNotEmpty && age != null && impairment != null;

  /// The user document, minus the timestamps the server writes.
  Map<String, Object?> toUserDocument(String uid) => {
        'uid': uid,
        'email': email.trim(),
        'role': role,
        'name': name.trim(),
        'displayName': name.trim(),
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
        if (role == 'vi') ...{
          if (age != null) 'age': age,
          if (impairment != null) 'impairment': impairmentKey(impairment!),
          // Every consent starts off, as it does for someone registering
          // themselves. The rules read this map; a missing one reads as no.
          'consent': {
            'location': false,
            'history': false,
            'recording': false,
            'activity': false,
            'faces': false,
          },
        },
      };
}

/// Why the account form cannot be sent, or null. [checkEmail] is false when
/// editing, where the email is the sign-in's and is not changed.
String? newAccountProblem({
  required String email,
  required String name,
  String age = '',
  String phone = '',
  required String role,
  bool checkEmail = true,
}) {
  if (checkEmail && emailAddressProblem(email) != null) {
    return 'Enter the email address the account is for.';
  }
  if (name.trim().isEmpty) return 'Enter their name.';
  if (age.trim().isNotEmpty) {
    final years = int.tryParse(age.trim());
    if (years == null || years < 1 || years > 120) {
      return 'Age should be a number of years.';
    }
  }
  if (phone.trim().isNotEmpty &&
      phone.replaceAll(RegExp(r'[^0-9]'), '').length < 7) {
    return 'That does not look like a phone number.';
  }
  if (role != 'vi' && role != 'guardian') return 'Choose a role.';
  return null;
}

/// An account an administrator has asked for, not yet registered.
class UserInvite {
  const UserInvite({required this.email, required this.role, this.deviceId});

  final String email;
  final String role;
  final String? deviceId;
}

/// One row of §1.2's user management table.
class AdminUserRow {
  const AdminUserRow({
    required this.uid,
    required this.role,
    this.displayName,
    this.email,
    this.deviceId,
    this.linkedTo = const [],
    this.impairment,
    this.category,
    this.phone,
    this.age,
    this.createdAt,
  });

  final String uid;

  /// 'vi', 'guardian' or 'admin'. §1.2 asks for all three.
  final String role;

  final String? displayName;
  final String? email;

  /// §1.2's "device connections". Optional — the requirement asks admins to
  /// manage them, not to insist every account has one.
  final String? deviceId;

  /// For a guardian, the users they watch. For a VI user, their guardians.
  final List<String> linkedTo;

  /// What the user said about their sight at "About you". Visually impaired
  /// accounts only, and only once they reached that step.
  final ImpairmentType? impairment;

  /// The older "blind" / "low vision" field, derived from how the phone is
  /// used rather than chosen. Only consulted when [impairment] is missing.
  final String? category;

  final String? phone;
  final int? age;
  final DateTime? createdAt;

  bool get isAdmin => role == 'admin';
  bool get isGuardian => role == 'guardian';
  bool get isVisuallyImpaired => role == 'vi';

  String get name => displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : (email ?? uid);

  /// [impairment], or the best the older [category] field can say.
  ImpairmentType? get knownImpairment =>
      impairment ??
      switch (category) {
        'blind' => ImpairmentType.blind,
        'low vision' => ImpairmentType.lowVision,
        _ => null,
      };
}
