import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/pairing/pairing_code.dart';
import 'package:impairgency/core/session_store.dart';
import 'package:impairgency/data/auth_service.dart';
import 'package:impairgency/data/guardian_onboarding.dart';
import 'package:impairgency/data/pairing_repository.dart';
import 'package:impairgency/guardian/guardian_registration.dart';

/// Firebase Auth as far as registration can see it.
class FakeAuth implements AuthService {
  FakeAuth({this.existing = const {}});

  /// Accounts that already exist: email to password.
  final Map<String, String> existing;

  @override
  String? uid;
  @override
  String? email;
  @override
  bool? verificationSent;

  int created = 0;
  int signedOut = 0;

  @override
  bool get isSignedIn => uid != null;
  @override
  bool get isEmailVerified => false;
  @override
  Stream<User?> get changes => const Stream.empty();

  @override
  Future<AuthFailure?> createAccount(String email, String password) async {
    if (existing.containsKey(email)) {
      return const AuthFailure('There is already an account with that email.',
          code: 'email-already-in-use');
    }
    created++;
    uid = 'g-${email.hashCode}';
    this.email = email;
    return null;
  }

  @override
  Future<String?> signIn(String email, String password) async {
    if (existing[email] != password) {
      return 'That email and password do not match an account.';
    }
    uid = 'g-${email.hashCode}';
    this.email = email;
    return null;
  }

  @override
  Future<void> signOut() async {
    signedOut++;
    uid = null;
    email = null;
  }

  @override
  Future<String?> sendPasswordReset(String email) async => null;
  @override
  Future<void> resendVerification() async {}
  @override
  Future<bool> refreshVerification() async => false;
  @override
  Stream<AuthAccount?> get accounts => const Stream.empty();
  @override
  Future<String?> sendVerification() async => null;
  @override
  Future<VerificationCheck> checkVerification() async =>
      VerificationCheck.notYet;
}

class FakeProfiles implements GuardianProfileStore {
  final Map<String, Map<String, Object?>> docs = {};
  int creates = 0;
  int merges = 0;
  Object? failWith;

  @override
  Future<Map<String, dynamic>?> read(String uid) async {
    if (failWith != null) throw failWith!;
    final doc = docs[uid];
    return doc == null ? null : Map<String, dynamic>.from(doc);
  }

  @override
  Future<void> create(String uid, Map<String, Object?> data) async {
    creates++;
    docs[uid] = {...data};
  }

  @override
  Future<void> merge(String uid, Map<String, Object?> data) async {
    merges++;
    docs[uid] = {...?docs[uid], ...data};
  }
}

class FakePairing implements PairingRepository {
  FakePairing(this.results);

  /// What each successive redeem returns.
  final List<RedeemResult> results;
  final List<String> redeemed = [];

  @override
  Future<RedeemResult> redeem(String input, {required String guardianId}) async {
    redeemed.add(input);
    return results.length > 1 ? results.removeAt(0) : results.first;
  }

  @override
  Future<String> issueCode(String ownerId, {DateTime? now}) =>
      throw UnimplementedError();
  @override
  Future<void> revokeCode(String code) => throw UnimplementedError();
  @override
  Stream<List<String>> watchedUsers(String guardianId) =>
      throw UnimplementedError();
  @override
  Future<List<String>> guardiansOf(String viUserId) =>
      throw UnimplementedError();
  @override
  Future<void> unpair(String guardianId, String viUserId) =>
      throw UnimplementedError();
}

const _ok = RedeemSucceeded(viUserId: 'vi-1', code: 'FH29MR47');
const _used = RedeemFailed(PairingCodeRejection.alreadyUsed);

GuardianRegistration registration({
  String email = 'ben@example.com',
  String password = 'longenough',
}) =>
    GuardianRegistration(
      name: 'Ben',
      email: email,
      password: password,
      phone: '09170000000',
      pairingCode: 'FH29MR47',
    );

void main() {
  late InMemorySessionStore store;
  setUp(() => store = InMemorySessionStore());

  GuardianOnboarding onboarding(FakeAuth auth, FakePairing pairing,
          FakeProfiles profiles) =>
      GuardianOnboarding(
          auth: auth, store: store, pairing: pairing, profiles: profiles);

  test('a new guardian gets an account, a document and a link', () async {
    final auth = FakeAuth();
    final profiles = FakeProfiles();
    final result =
        await onboarding(auth, FakePairing([_ok]), profiles).register(registration());

    expect(result, isNull);
    expect(auth.created, 1);
    expect(profiles.docs[auth.uid]!['role'], 'guardian');
    expect((await store.cachedProfile()).role, 'guardian');
  });

  test('pressing again after a refused code links the account that exists',
      () async {
    // The bug, step by step: the first press made the account and the code
    // was refused; the second press tried to make the account again.
    final auth = FakeAuth();
    final profiles = FakeProfiles();
    final pairing = FakePairing([_used, _ok]);
    final flow = onboarding(auth, pairing, profiles);

    final first = await flow.register(registration());
    expect(first!.field, RegisterField.code);
    expect(first.accountReady, isTrue);

    final second = await flow.register(registration());
    expect(second, isNull);
    expect(auth.created, 1, reason: 'the account is never made twice');
    expect(profiles.creates, 1);
    expect(profiles.merges, 1,
        reason: 'the second press only refreshes what the form can change');
    expect(pairing.redeemed, hasLength(2));
  });

  test('an account made before the app was closed is signed back into',
      () async {
    final auth = FakeAuth(existing: {'ben@example.com': 'longenough'});
    final profiles = FakeProfiles();
    final result = await onboarding(auth, FakePairing([_ok]), profiles)
        .register(registration());

    expect(result, isNull);
    expect(auth.isSignedIn, isTrue);
  });

  test('an email taken by someone else is refused under the email', () async {
    final auth = FakeAuth(existing: {'ben@example.com': 'not-this-one'});
    final result = await onboarding(auth, FakePairing([_ok]), FakeProfiles())
        .register(registration());

    expect(result!.field, RegisterField.email);
    expect(result.accountReady, isFalse);
    expect(result.message, contains('I already have an account'));
    expect((await store.cachedProfile()).role, isNull,
        reason: 'the cached role goes back to what it was');
  });

  test("a visually impaired user's account is not turned into a guardian",
      () async {
    final auth = FakeAuth(existing: {'ben@example.com': 'longenough'});
    final profiles = FakeProfiles();
    final uid = 'g-${'ben@example.com'.hashCode}';
    profiles.docs[uid] = {'uid': uid, 'role': 'vi'};

    final result = await onboarding(auth, FakePairing([_ok]), profiles)
        .register(registration());

    expect(result!.field, RegisterField.email);
    expect(auth.signedOut, 1);
    expect(profiles.docs[uid]!['role'], 'vi');
  });

  test('a failure after the account exists keeps the account', () async {
    final auth = FakeAuth();
    final profiles = FakeProfiles();
    final flow = onboarding(auth, FakePairing([_ok]), profiles);
    await flow.register(registration(email: 'amy@example.com'));
    profiles.failWith = StateError('offline');

    final result = await flow.register(registration(email: 'amy@example.com'));

    expect(result, isNotNull);
    expect(result!.message, contains('Check your connection'));
    expect(auth.isSignedIn, isTrue);
  });
}
