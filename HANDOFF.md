# Where we left off — 2026-09-08

## Done and committed (`75b2015`)

1. **Android could never launch.** `MainActivity.kt` declared `package
   ph.impairgency.impairgency`; the Gradle namespace is `ph.impairgency.app`.
   The manifest's `.MainActivity` resolved to a class that was never compiled.
   Broken since the first scaffold commit `0745c29` — no Android build had ever
   started. Release was worse: R8 stripped the unreachable class, so release
   APKs shipped with no launcher activity at all. Fixed by moving the file.
2. **"Sign in" was a dead end.** `onSignIn` navigated to `Routes.createAccount`
   and no sign-in screen existed. Added `lib/vi/onboarding/sign_in_screen.dart`,
   `Routes.signIn`, and the redirect handling. `AuthService.signIn` already
   worked — only the screen and route were missing.

`flutter analyze` clean, 490 tests pass. Verified on device: Sign in reaches the
screen, and a bad credential surfaces Firebase's own message as a `content-desc`
(so TalkBack announces it).

## NOT verified — pick up here

- **Create-account and sign-in end to end.** Only the failure path was exercised
  on device. The app supports `--dart-define=USE_EMULATOR=true` (auth emulator
  on 9099, see `lib/main.dart`), so seed a test user in the *emulator* rather
  than creating a real account:
  ```
  firebase emulators:start
  flutter run --dart-define=USE_EMULATOR=true -d <device>
  ```
- **Object detection has never been run.** Not once this session — the emulator
  camera is a synthetic scene, so it proves nothing.

## Object detection — read before touching it

**It is not YOLO11.** `assets/models/ssd_mobilenet.tflite` is SSD MobileNet V1,
quantised, 300x300 (graph nodes are `FeatureExtractor/MobilenetV1/...`). There is
no YOLO anywhere in the repo. `lib/data/scan_service_io.dart` is written against
SSD's 4-output layout and matches the model correctly.

**It cannot detect stairs.** The 90 COCO labels contain no `stairs`, no `step`,
no `curb`. `door` (index 70) is one of COCO's *placeholder* labels — in the label
map but never trained — so it will effectively never fire. Same for `window`,
`mirror`, `desk`, `street sign`, `hat`, `shoe`, `eye glasses`, `plate`,
`blender`, `hair brush`.

This is a fall risk for the users this app is for, and `docs/BUILD_PLAN.md`
already flags it as unbuilt: *"Stairs specifically is a fall risk and should be
attempted — a dedicated class, or a floor-plane heuristic, and an honest
confidence threshold that stays silent rather than guessing."*

Getting stairs requires one of:
- a model trained with a stairs class (custom dataset — YOLO11 or otherwise),
- a floor-plane / depth heuristic,
- honest silence plus a spoken limitation, which is what the safety notice
  currently implies but does not name.

Swapping SSD for YOLO11 means rewriting `_process()` in
`lib/data/scan_service_io.dart`: YOLO has a single output tensor needing
transpose and NMS, not SSD's four pre-processed ones.

## Known issues, not addressed

- `flutter_tts` and `speech_to_text` still apply the legacy Kotlin Gradle
  Plugin; Flutter warns future versions will fail to build. Both are load-bearing
  for a blind-user app.
- No sign-out anywhere in the VI app.
- Android emulator crashes under `-gpu host` (hanging QEMU threads after Vulkan
  init). Use `-gpu swiftshader_indirect`.

## Environment (set up this session, persists)

Flutter is not on the Bash PATH; prefix commands with:
```
export PATH="$HOME/development/flutter/bin:$HOME/.pub-cache/bin:$PATH"
```
AVD `impairgency_api36` (Pixel 7, Android 16) now exists. `flutter doctor` is
fully green including the Android toolchain.
```
~/Library/Android/sdk/emulator/emulator -avd impairgency_api36 -gpu swiftshader_indirect
```
