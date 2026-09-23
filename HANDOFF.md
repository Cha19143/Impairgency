# Where we left off — 2026-09-23

## Tester feedback round 4

The testers' list of September 18, on branch `claude/tester-feedback-sept-18`,
from the plan agreed on 2026-09-23: PR calmadex/impairgency#87.
`flutter analyze` is clean; **1418** Flutter tests, **96** rules tests and
**16** browser tests pass. A release APK, the web app and an unsigned release
iOS build all build. The checklist is in [`docs/TASKS.md`](docs/TASKS.md),
"Tester feedback round 4".

1. **SOS.** "Cancel" acts on the first partial: the hint no longer says it
   mid-sentence. The `sos_events` record is written before the dialler
   opens, under an id chosen then, so "I am okay" after the call - said or
   pressed - can mark it resolved; the guardian's phone then says so.
2. **Admin.** System health lists every SOS of the last 30 days, with Mark
   resolved (the rules let an administrator change three fields and nothing
   else). Nothing ever wrote `session_summaries`; `JourneyRecorder` now
   records each journey and publishes its summary, with history consent
   only, so Overview and System health have something to show.
3. **Voice.** Near misses (`core/voice/fuzzy.dart`), Tagalog particles,
   "stop", "back", friends and hands-free on every screen, a failing
   microphone tried again on the next screen, and dictation that takes edits
   (`core/voice/dictation_edit.dart`).
4. **Smart assistance.** Results first, numbered and read out; search
   without a position; turns no longer dropped; "Keep going" between turns.
5. **Scan.** The banding heuristic is gone. A one-class YOLO11n
   (`data/stairs_detector_io.dart`) runs beside the COCO model every 500 ms.
   Friends from the home screen, with who-do-I-know, rename and forget
   everyone.

Since then (the same day): the branch is pushed and PR #87 open. **Rules,
indexes and hosting deployed** from `fadb8f0`: the `session_summaries`
index was missing live and is added, both `sos_events` indexes were there,
and the live dashboard was checked to be this build and to serve none of
the model files. On release `apk-2026-09-10`, retitled "Android test build
2026-09-23": `impairgency-fadb8f0-(arm64-)release.apk`, without the stairs
model.

**The stairs model** was trained the same day on this Mac, from Open Images'
2,478 photographs of stairs (`a1a9ca2` fixed the tools first: the export
path, the run folder, the camera size the measurement simulates, and
negatives it never trained on). The first model (`8b10561`) took a quarter
of zebra crossings for stairs, because Open Images' human-checked labels
have no crossing to train against; its APKs,
`impairgency-8b10561-(arm64-)release.apk`, are on the release. Trained again
with 172 photographs from Open Images' machine labels as negatives, 58 of
them crossings, it finds 56% of close stairs at 0.45 on photographs neither
model saw, and names stairs on 5% of photographs with none - about one
zebra crossing in ten. At 0.55 it finds 49%, short of the 70% "Stop" needs,
so **"Stop" stays off** and stairs are named from 0.45.
`assets/models/yolo11n_stairs.tflite`, 10.6 MB; hash and table in
[`docs/VISION.md`](docs/VISION.md), "Stairs".

## Waiting on someone

- **Merge PR #87.** Its CI fails only at the artifact upload: the
  account's Actions storage (500 MB) is full with five APK artifacts of
  about 145 MB each, and every run since September 16 has failed there.
  Analyze, the tests and both APK builds pass. `5dba0a5` makes each run keep
  only the arm64 APK, for three days. The five old artifacts are Dex's to
  delete, and GitHub recounts every 6 to 12 hours:

  ```bash
  gh api /repos/calmadex/impairgency/actions/artifacts --paginate --jq '.artifacts[] | select(.name=="impairgency-apk") | .id' | xargs -I{} gh api -X DELETE /repos/calmadex/impairgency/actions/artifacts/{}
  ```
- **Tester APKs with the retrained stairs model**: built, not uploaded -
  asks first. The release has the first model's (`8b10561`).
- **Rugs and tiled floors for the stairs model**: Open Images gave three of
  each. Phone photographs (`tool/fetch_stairs.py --negatives <folder>`),
  then train again (about 40 minutes) and measure.
- **Superseded APKs** on the release: the `8c4014a` tester pair, `836fb6b`,
  `8424e2f`, and the `7ac4791` stairs check, whose heuristic is gone. Delete
  them once the new ones are confirmed to install. The `8c4014a`
  depth-check pair is still the depth check.
- **Three live Firestore indexes** that `firestore.indexes.json` does not
  have: `sessions (viUid, startedAt)`, `sos_events (resolved, firedAt)` and
  `sos_events (viUid, firedAt)`, from an older schema.
  `firebase deploy --only firestore:indexes --force` removes them, once
  nothing old reads them.
- **The "Feedback September 18" session** still has this round's plan open
  for approval; approving it there would do the round again.
- **On the emulator**: a journey with history on writes a summary, and with
  it off nothing. It needs live OSRM answers, or a fake route.

## Check on a real phone

- SOS: "cancel" over the countdown's own voice; fire, hang up, "I am okay";
  the guardian's card and the dashboard row.
- Dictation edits and spelling; a Filipino name and a Gmail address.
- A walked route: numbered results, "Keep going", standing still for 40 s.
- A journey with history on reaching Overview; with it off, nothing.
- "Hello friend Sam" from the home screen, and the views counted aloud.
- Stairs (`docs/DEMO.md`, step 12): real flights up and down, indoors and
  out; a tiled floor, a zebra crossing and a striped rug. Every miss and
  false alarm into `docs/VISION.md`.

---

# Where we left off — 2026-09-16

## Tester feedback round 3

The testers' list of September 16, on branch `claude/tester-feedback-sept-16`,
from the plan agreed that day: PR calmadex/impairgency#86.
`flutter analyze` is clean; **1297** Flutter tests, **90** rules tests
and **13** browser tests pass. A release APK, the web app and an unsigned
release iOS build all build. The checklist is in [`docs/TASKS.md`](docs/TASKS.md), "Tester feedback round 3".

1. **Voice on every screen.** Hands-free listens on every screen of the user
   app, through a fallback scope the router sets (`AppSession._listenOn`): not
   on the first safety notice, not during SOS, not in the guardian app. Every
   `ViScreen` offers the microphone. Any button is pressed by saying its label
   (`core/voice/spoken_targets.dart`, `vi/voice_targets.dart`,
   `vi/widgets/press_by_voice.dart`). Forms are dictated with read-back
   (`core/voice/dictation.dart`, `VoiceController.dictate`,
   `vi/widgets/dictated_field.dart`, `vi/widgets/voice_form.dart`), passwords
   never.
2. **Admin sidebar.** A roster read with no answer was remembered as "not an
   administrator". `AdminRepository.rosterCheck` now tells a refusal from no
   answer; the session retries and the sign-in page says it is checking. Pages
   explain an unreachable database and time out; the open section reloads when
   clicked.
3. **Scan.** "Path looks clear" is "No known objects in view", said rarely.
   Classes are weighted (`core/vision/class_risk.dart`); a handheld object is
   never a Stop. A depth model for walls (`core/vision/depth.dart`,
   `data/depth_estimator_io.dart`) is wired in **behind
   `--dart-define=DEPTH_WARNINGS=true`, and its 66 MB file is not in the
   repository**.
4. **A map.** Directions moved to `/journey` (`vi/screens/journey_screen.dart`),
   with the route drawn on OpenStreetMap tiles; Scan is surroundings only. Both
   warn through one `SurroundingsWatch`. "Somewhere else" leads the chooser.
5. **SOS cancel by voice.** The countdown listened once and stopped; a
   `CancelListener` now reopens the microphone for as long as it runs, acts on
   a partial "cancel", and keeps listening until the dialler opens
   (`SosEngine.fire(cancelled:, onCommitted:)`). The countdown no longer talks
   over its own "say cancel".

Since then (the same evening): MobileFaceNet added (`a314026`), with its hash
and shapes in `docs/VISION.md`; MiDaS downloaded for the depth check and kept
out of git. **Hosting deployed** from `8c4014a`, and the live dashboard checked
to hold the new build and none of the model files. On release
`apk-2026-09-10`: `impairgency-8c4014a-(arm64-)release.apk` for testers, and
`impairgency-8c4014a-depth-check-(arm64-)release.apk` with the depth model and
flag, not for testers. The tester APK was installed on both emulators: the
guardian's app opens without a microphone; the user app's Settings, Scan and
Smart assistance work, with hands-free listening on Settings and "Somewhere
else" asking by voice. That run found the Settings switch still naming four
screens (`8c4014a`). SOS was not fired there: the emulators use the live
project.

## Waiting on someone

- **Merge PR #86** once CI is green.
- **Superseded APKs** stay attached to the release (`836fb6b`, `8424e2f`,
  `7ac4791` stairs check), marked as such in the notes; delete them when the
  new ones are confirmed to install.

## Check on a real phone

- Dictation: Filipino names and a Gmail address through the platform
  recogniser; the first run's microphone prompt on the welcome screen.
- A "cancel" heard over the countdown's own voice, on Android and on iOS.
- The camera handed from Scan to the map and back; a walk in Malolos on the
  map.
- Pressing buttons by voice with hands-free on in a noisy room: anything
  pressed that was not asked for.
- With the depth file and flag: the checklist in `docs/VISION.md`, "Depth".

---

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
