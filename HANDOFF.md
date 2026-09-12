# Where we left off — 2026-09-12

## What happened

The updated main was installed on a real iPhone 15 Pro Max and on a wiped
Pixel 7 / Android 16 emulator, and every screen was driven by hand with
screenshots and logcat. Each bug below was found that way and verified fixed
the same way. `flutter analyze` is clean; 779 tests pass.

Test APKs live on the private GitHub release `apk-2026-09-10`
(`gh release view apk-2026-09-10`). Replace its assets rather than making a
new release; the notes there list every fix.

## Fixed this round

1. **Android could never launch.** `MainActivity.kt` sat in
   `ph.impairgency.impairgency`; the namespace is `ph.impairgency.app`. Moved.
2. **Release APK hung on the splash on a fresh install.** R8 under AGP 9
   stripped the no-arg constructors of the Firebase registrars (Crashlytics,
   Messaging, Installations); Firebase init threw before the first frame.
   One keep rule in `android/app/proguard-rules.pro`.
3. **Scan's Back button crashed the app** (SIGSEGV in
   `libtensorflowlite_jni`, DartWorker thread). `ScanService.dispose()`
   closed the interpreter under an inference still running on the worker
   isolate. It now waits for the run in flight, capped at 2 s.
4. **Settings' Emergency contacts, Guardian and Connect a device bounced to
   home.** The redirect sent any finished user off `/onboarding/*`.
   `Routes.revisitable` names the three that Settings reopens; `_step()` in
   `router.dart` returns them to Settings afterwards.
5. **Emergency contact read "Not set" after every launch; contact screen
   opened blank.** `acknowledgeSafety()` rebuilt the session from five
   fields and dropped contacts, consent, guardian count and uid. A Save on
   that blank screen would have written `[]` over the real contact.
6. **Safety notice, then Welcome, on every cold start.** The router was built
   before `load()` and before Firebase's first auth event. `app.dart` now
   waits for both (`AppSession.firstAuth`, 5 s cap) behind a navy scaffold.
7. **"Stop directions" did nothing.** `go()` to the current route is a no-op,
   so the scan screen was never rebuilt. It forgets the destination itself.

## Verified working on device / emulator

iPhone: launch, safety notice spoken to the end, scan with the real camera
(YOLO11 announces chair / person / bed / laptop with distance and side).
Emulator: dashboard (scan, smart assistance with saved places, read text end
to end, SOS countdown + cancel, tap to speak with its no-mic fallback, what
can I say), all eight Settings entries, consent save / turn everything off,
sign out, welcome / create-account / sign-in reachable on a wiped install.

## Known, not fixed

- Camera preview is not clipped to its card on Scan and Read text (white
  strip above, colour spill below). Cosmetic.
- Android system back exits the app from any screen: every navigation is
  `go()`, which replaces the stack. A blind user's back gesture leaves the app.
- Screens are built from `session.state` at navigation time and do not
  rebuild when the profile refresh from Firestore lands.
- `flutter_tts` and `speech_to_text` still apply the legacy Kotlin plugin.
- YOLO11n is AGPL-3.0 (see pubspec.yaml). Distribution needs the source
  published under the same terms or an Ultralytics licence.

## Environment notes

- Flutter is not on the Bash PATH:
  `export PATH="$HOME/development/flutter/bin:$HOME/.pub-cache/bin:$PATH"`
- **Do not run `dart format`.** The repo is in the pre-3.7 style; the SDK's
  formatter rewrites whole files.
- Emulator: `~/Library/Android/sdk/emulator/emulator -avd impairgency_api36
  -gpu swiftshader_indirect`. Drive it with `adb shell input tap` and
  `adb exec-out screencap -p`; `uiautomator dump` lags Flutter's semantics
  and misled once, so trust screenshots.
- iPhone: `flutter build ios --release`, then `xcrun devicectl device
  install app`. `idevicesyslog -p Runner` (brew libimobiledevice) shows what
  the app speaks; screenshots and remote taps are not possible on iOS 26.
