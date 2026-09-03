# ImpairGency

Assistive navigation, environment awareness and emergency contact for visually
impaired users — with a guardian app and a web admin dashboard.

One Flutter codebase, three platforms, split at the router:

| Platform | Build | Entry |
|---|---|---|
| Visually impaired user app | `flutter build apk` / `ios` | `/` |
| Guardian app | same binary, role-routed | `/guardian` |
| Admin dashboard (**web**) | `flutter build web` | `/admin` |

`lib/app/routes.dart` enforces the split: on web the app *is* the dashboard and
nothing else; on mobile the dashboard is unreachable. See
[`docs/BUILD_PLAN.md`](docs/BUILD_PLAN.md) for scope, sequence and what is
deliberately out of scope.

## Layout

```
lib/
  app/        router, redirect rule, theme
  core/       platform-agnostic and Flutter-free — unit tested without a binding
    a11y/     WCAG contrast maths
    voice/    command vocabulary and matching
  data/       Firestore repositories, device services
  vi/         visually impaired user app
  guardian/   guardian app
  admin/      web dashboard
  shared/     accessible widgets used by more than one app
```

`core/` avoids Flutter imports on purpose. Everything in it is testable in
milliseconds, which is what makes the accessibility and safety rules below
enforceable rather than aspirational.

## Getting started

```bash
flutter pub get
flutter test
flutter run
```

The app runs on a clean checkout without Firebase. To connect it:

```bash
flutterfire configure --project=<your-new-project-id>
```

then uncomment the `Firebase.initializeApp` block in `lib/main.dart`.

### Deploying rules — do this before storing any real data

```bash
firebase deploy --only firestore:rules
```

Firestore rules only. **`storage:rules` is deliberately not deployed:** a Cloud
Storage bucket requires the Blaze plan, and this project runs on the free tier.
Nothing in scope stores a file, so there is no bucket to protect. The rules are
still written and still verified — the Storage emulator provisions a local
bucket at no cost, so `tool/test_rules.sh` proves them without a billing
account. Adding `storage:rules` to the command above will fail until a bucket
exists.

`firestore.rules` and `storage.rules` are in version control on purpose. The
previous project had neither, which meant nobody on the team could review who
could read a user's emergency contacts.

## What the tests enforce

Not coverage for its own sake — each of these is a defect the previous project
shipped, turned into a failing test.

| Test | Guards against |
|---|---|
| `test/core/contrast_test.dart` | Button labels that fail WCAG AA. The old app rendered white on `#00FFFF`, about 1.1:1. |
| `test/core/routing_test.dart` | An admin route reachable without an admin. Onboarding that cannot resume after a crash. A completion screen that routes back to sign-in. |
| `test/core/voice_commands_test.dart` | The vocabulary screen drifting from what the parser accepts. Cancel words that hijack everyday speech. |
| `test/core/safety_notice_test.dart` | Copy that hedges instead of naming what the app misses, or claims the environment is safe. |
| `test/rules/firestore.test.js` | A guardian reading a user they were never paired with. Location leaking after consent is revoked. A client making itself an admin. A pairing code redeemed twice. |

```bash
flutter test                 # 55 unit and widget tests
tool/test_rules.sh           # 28 security rules tests, on the emulator
flutter build apk && flutter build ios && flutter build web
```

`tool/test_rules.sh` needs no Firebase project and no network — it runs against
the emulator with a demo project id. It does need a JDK 21+; the script points
itself at a Homebrew `openjdk@21` if your default `java` is older.

All three builds, every time. Defects this project's predecessor hit were
invisible to `analyze` and `test`.

## Accessibility is the acceptance criterion

The manual pass that matters: complete the whole of onboarding with **VoiceOver
on and Screen Curtain enabled** — screen fully black. Anything that cannot be
finished that way is a defect, not a polish item.

## Ported from `cprwire`

Carried over: the voice command vocabulary and its tests, the object-detection
approach, the palette. Left behind: FlutterFlow's generated scaffolding, the
`cprwire` package name, the mocked screens, and a Firebase project whose rules
nobody could see.
