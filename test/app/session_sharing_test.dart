import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/data/location_sharer.dart';

/// When the session turns location sharing on and off.
class _Recorder implements LocationSharing {
  final log = <String>[];
  String? uid;
  bool history = false;

  @override
  bool get isSharing => uid != null;

  @override
  void start(String uid, {required bool recordHistory}) {
    this.uid = uid;
    history = recordHistory;
    log.add('start $uid history=$recordHistory');
  }

  @override
  void stop() {
    if (uid != null) log.add('stop');
    uid = null;
  }

  @override
  Future<void> forget(String uid) async => log.add('forget $uid');
}

void main() {
  late _Recorder sharer;
  late AppSession session;

  SessionState viUser({
    Map<String, bool> consent = const {'location': true, 'history': false},
    bool signedIn = true,
    bool guardian = false,
  }) =>
      SessionState(
        uid: 'u1',
        signedIn: signedIn,
        isGuardian: guardian,
        safetyAcknowledged: true,
        completedSteps: Routes.onboardingFlow.toSet(),
        consent: consent,
      );

  setUp(() {
    sharer = _Recorder();
    session = AppSession(sharer: sharer);
  });

  test('sharing starts when a signed-in user has said yes', () {
    session.update(viUser());
    expect(sharer.log, ['start u1 history=false']);
  });

  test('and records the trail only with the second consent', () {
    session.update(viUser(consent: {'location': true, 'history': true}));
    expect(sharer.history, isTrue);
  });

  test('nothing starts without consent, signed out, or for a guardian', () {
    session.update(viUser(consent: {'location': false}));
    session.update(viUser(signedIn: false));
    session.update(viUser(guardian: true));
    expect(sharer.log, isEmpty);
  });

  test('withdrawing consent stops sharing and removes the point', () {
    session.update(viUser());
    session.update(viUser(consent: {'location': false}));
    expect(sharer.log, ['start u1 history=false', 'stop', 'forget u1']);
  });

  test('signing out stops it, without a forget it cannot address', () {
    session.update(viUser());
    session.update(const SessionState(safetyAcknowledged: true));
    expect(sharer.log, ['start u1 history=false', 'stop']);
  });

  test('putting the app away pauses it; bringing it back resumes', () {
    session.update(viUser());
    session.setForeground(false);
    session.setForeground(true);
    expect(sharer.log, [
      'start u1 history=false',
      'stop',
      'start u1 history=false',
    ]);
  });

  test('a session built without a sharer is unaffected', () {
    final bare = AppSession();
    bare.update(viUser());
    bare.setForeground(false);
    expect(bare.state.uid, 'u1');
  });
}
