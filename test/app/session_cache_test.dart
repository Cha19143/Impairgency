import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/session_store.dart';

/// The emergency contact the tester saved and SOS never saw.
///
/// The contact was written to Firestore, and the device's copy - the only
/// thing SOS and Settings read - was refreshed at sign-in and never again.
void main() {
  Future<AppSession> signedIn(SessionStore store) async {
    final session = AppSession(store: store);
    await session.load();
    // What bindAuth does when Firebase reports a user: the loaded profile
    // is carried forward, not discarded.
    session.update(SessionState(
      uid: 'u1',
      signedIn: true,
      safetyAcknowledged: true,
      completedSteps: Routes.onboardingFlow.toSet(),
      consent: session.state.consent,
      contactName: session.state.contactName,
      contactNumber: session.state.contactNumber,
      guardianCount: session.state.guardianCount,
    ));
    return session;
  }

  test('a saved contact is visible to SOS immediately', () async {
    final session = await signedIn(InMemorySessionStore(acknowledged: true));
    expect(session.state.contactNumber, isNull);

    await session.rememberContact('Mum', '+639170000000');

    expect(session.state.contactName, 'Mum');
    expect(session.state.contactNumber, '+639170000000');
  });

  test('and survives a relaunch with no network', () async {
    final store = InMemorySessionStore(acknowledged: true);
    final first = await signedIn(store);
    await first.rememberContact('Mum', '+639170000000');

    final relaunched = await signedIn(store);
    expect(relaunched.state.contactNumber, '+639170000000');
  });

  test('remembering a contact does not forget consent, or the other way round',
      () async {
    final session = await signedIn(InMemorySessionStore(acknowledged: true));
    await session.rememberConsent({'location': true});
    await session.rememberContact('Mum', '0917');
    expect(session.state.consent['location'], isTrue);
    expect(session.state.contactNumber, '0917');

    await session.rememberConsent({'location': false});
    expect(session.state.contactNumber, '0917');
    expect(session.state.consent['location'], isFalse);
  });
}
