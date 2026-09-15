# Where we left off — 2026-09-15

## Tester feedback round 2

The testers' list of September 15, all of it, on branch
`claude/tester-feedback-sept-15`. Nothing committed or deployed yet.
`flutter analyze` is clean; **1136** Flutter tests, **90** rules tests and
**12** browser tests pass. A release APK and the web app build. The checklist
is in [`docs/TASKS.md`](docs/TASKS.md), "Tester feedback round 2".

1. **Guardian Create account lands on the dashboard.** It had worked and not
   navigated; a second press now carries on with the account already made.
2. **Email verification for new accounts** (`/verify-email`). Cutoff in
   `lib/core/auth/email_verification.dart`; older accounts are not held.
3. **Admin Users:** filters with counts, search, add (secondary Firebase app,
   the person sets their own password by email), edit, remove (tombstone in
   `removed_accounts`, enforced by the rules; the phone signs out).
4. **Read Text:** buttons stack on phones; "read" / "basahin", pause, next,
   again by voice.
5. **Voice:** Tap to speak fixed; hands-free listening (Settings switch, on by
   default on Android, off on iOS until tried); the app's own speech filtered
   out; many more commands, "take me home" included.
6. **Directions:** OSRM walking routes (routing.openstreetmap.de) followed turn
   by turn, rerouting within limits, straight line as the named fallback;
   Photon place search by voice and typed; street names in "where am I".
7. **Friends:** "hello friend Sam" asks Sam and saves five views of the face on
   the phone; "Your friend Sam is approaching"; People I know in Settings;
   deleted with the consent and at sign-out. **Needs the two face models,
   which are not downloaded** — see `docs/VISION.md`, "Faces".

Since then (2026-09-16): **Firestore rules and hosting deployed**; PR
calmadex/impairgency#83 open; real OSRM and Photon answers recorded as
fixtures, which caught place search merging two branches of one shop; the
BlazeFace model added and checked; the test APKs on release `apk-2026-09-10`
updated.

## Waiting on someone

- **MobileFaceNet** — agree the exact file and the weights' licence (see
  `docs/VISION.md`, "Faces"). Until then recognition says it is unavailable.
- **Two superseded APKs** are still attached to the release, marked as such;
  delete them when the new ones are confirmed to install.
- **iOS build** — the build Mac's Xcode licence has not been accepted
  (`sudo xcodebuild -license`), so git and `flutter build ios` fail with exit
  69 in a normal shell. The session worked around it with
  `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.

## Check on a real phone

- Hands-free on Android: whether the recogniser beeps on every restart, and
  whether starting it ducks the speech. Tried only against fakes.
- A route walked outdoors: prompt timing, false off-route alarms at 10–20 m
  GPS error, how FOSSGIS and Photon answer from the Philippines.
- Face recognition, once the models are in: threshold, distance, light, heat
  and battery with YOLO and both face models running.
- The verification email: delivery, spam folder.

---

# Where we left off — 2026-09-13

## Guardian side, this round

Built and verified with two emulators (guardian on 5554, a signed-in user
on 5556 with `adb emu geo fix`), one at a time - this Mac cannot run both.

1. **Location sharing.** Nothing in the user app ever published a position;
   the guardian card said "none recorded yet" forever. `LocationSharer`
   (`lib/data/location_sharer.dart`) polls every 30 s while the app is in
   the foreground and `consent.location` is on, and writes `users/{uid}
   .lastFix`. `SharePolicy` sends the first reading, a move of 15 m, or a
   5-minute heartbeat; never a cell-tower guess. It asks the OS for
   permission once, because nothing else on a normal path does. Turning
   consent off deletes the field. The guardian reads `lastFix` off the
   profile; `location_history/fixes` stays as a fallback.
2. **Recent activity.** New consent `activity` ("Share what the app
   notices"), new collection `users/{uid}/activity` (rules deployed
   2026-09-13), `ActivityRepository`, and `AppSession.recordActivity`.
   Rows: obstacle warnings (throttled to one per object per minute), the
   first line of a page read, and destinations set. The card shows three.
3. **Live location.** `LiveLocationScreen` - flutter_map + OpenStreetMap
   tiles, marker, accuracy circle, "Updated N ago, to within M metres",
   rebuilds on each new fix. Route `/guardian/live?uid=`.
4. The pairing-code screen has a Back arrow; before, system back left the
   app.

Not built: "Mode: Active now" and battery on the mock. SOS still lives on
its own line, not in the activity feed.

## Seen, not fixed

- A `saved_places` write was refused by the rules once, right after
  sign-in on a fresh device; later writes went through. Probably the
  write racing the auth token. Worth a look.
- Back from Saved places goes to Settings even when reached from Smart
  assistance.
- The guardian's log shows a permission-denied read of `admins/{uid}` on
  every launch: the admin check for a non-admin. Harmless noise.
- Xcode has no Apple ID signed in, so no iPhone build can be signed until
  someone signs in (Settings, Accounts). The iPhone still has the
  2026-09-12 build.

---

# Previous round — 2026-09-12

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
