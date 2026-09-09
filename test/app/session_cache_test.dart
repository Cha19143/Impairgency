import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/contacts/emergency_contact.dart';
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
      contacts: session.state.contacts,
      guardianCount: session.state.guardianCount,
    ));
    return session;
  }

  test('a saved contact is visible to SOS immediately', () async {
    final session = await signedIn(InMemorySessionStore(acknowledged: true));
    expect(session.state.contactNumber, isNull);

    await session.rememberContacts(
        [const EmergencyContact(name: 'Mum', number: '+639170000000')]);

    expect(session.state.contactName, 'Mum');
    expect(session.state.contactNumber, '+639170000000');
  });

  test('and survives a relaunch with no network', () async {
    final store = InMemorySessionStore(acknowledged: true);
    final first = await signedIn(store);
    await first.rememberContacts(
        [const EmergencyContact(name: 'Mum', number: '+639170000000')]);

    final relaunched = await signedIn(store);
    expect(relaunched.state.contactNumber, '+639170000000');
  });

  test('several contacts keep their order, which is the calling order',
      () async {
    final session = await signedIn(InMemorySessionStore(acknowledged: true));
    await session.rememberContacts(const [
      EmergencyContact(name: 'Mum', number: '0917'),
      EmergencyContact(name: 'Dad', number: '0918'),
      EmergencyContact(name: 'Mum again', number: '0917'),
    ]);
    expect(session.state.contacts.map((c) => c.name), ['Mum', 'Dad'],
        reason: 'the same number twice is one person');
    expect(session.state.contactName, 'Mum', reason: 'first is rung first');
  });

  test('remembering a contact does not forget consent, or the other way round',
      () async {
    final session = await signedIn(InMemorySessionStore(acknowledged: true));
    await session.rememberConsent({'location': true});
    await session.rememberContacts(
        [const EmergencyContact(name: 'Mum', number: '0917')]);
    expect(session.state.consent['location'], isTrue);
    expect(session.state.contactNumber, '0917');

    await session.rememberConsent({'location': false});
    expect(session.state.contactNumber, '0917');
    expect(session.state.consent['location'], isFalse);
  });
}
