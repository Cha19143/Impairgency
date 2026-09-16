import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/app/router.dart';
import 'package:impairgency/app/routes.dart';
import 'package:impairgency/core/session_store.dart';

import '../vi/voice_fakes.dart';

void main() {
  Future<(AppSession, OpenWindows)> start({bool acknowledged = true}) async {
    final windows = OpenWindows();
    final session = AppSession(
      store: InMemorySessionStore(acknowledged: acknowledged),
      recognizer: windows,
    );
    await session.load();
    await session.setHandsFree(true);
    session.voice; // made on first use, as the app makes it
    return (session, windows);
  }

  Future<void> stop(AppSession session) async {
    await session.setHandsFree(false);
    await pumpEventQueue();
  }

  test('every screen of the app listens hands-free, not only four', () async {
    // Only the dashboard, Scan, Read Text and Smart assistance attached a
    // scope, so on Settings, the forms and the lists the microphone stayed
    // shut with hands-free on.
    final (session, windows) = await start();

    for (final route in [
      Routes.settings,
      Routes.savedPlaces,
      Routes.emergencyContact,
    ]) {
      session.routeChanged(route);
      // The window the last screen had is closed; the next opens after the
      // loop's short pause.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(windows.open, isTrue, reason: route);
    }
    await stop(session);
  });

  test('the SOS flow is left to its own listening', () async {
    // A hands-free window between two of the countdown's would take the
    // microphone and hear "cancel" as nothing.
    final (session, windows) = await start();
    session.routeChanged(Routes.home);
    await pumpEventQueue();
    expect(windows.open, isTrue);

    session.routeChanged(Routes.sos);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(windows.open, isFalse);
    await stop(session);
  });

  test("the guardian's app does not listen", () async {
    final (session, windows) = await start();
    session.update(session.state.copyWith(signedIn: true, isGuardian: true));
    session.routeChanged(Routes.guardianHome);
    await pumpEventQueue();
    expect(windows.sessions, isEmpty);
    await stop(session);
  });

  test('the first safety notice is heard out before the microphone is asked '
      'for', () async {
    final (session, windows) = await start(acknowledged: false);
    session.routeChanged(Routes.safety);
    await pumpEventQueue();
    expect(windows.sessions, isEmpty,
        reason: 'the permission prompt would land on the notice');

    await session.acknowledgeSafety();
    session.routeChanged(Routes.welcome);
    await pumpEventQueue();
    expect(windows.open, isTrue);
    await stop(session);
  });
}
