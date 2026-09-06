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

`lib/main.dart` initialises Firebase against the project in
`lib/firebase_options.dart`. To point a clone at your own:

```bash
flutterfire configure --project=<your-new-project-id>
```

To run against the local emulators instead of the live project:

```bash
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

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
| `test/e2e/auth-gate.spec.js` | A correct password that redisplays the login form. An admin route reachable without an admin. The dashboard is driven in a real browser, so these are caught in the build that ships rather than in a test harness. |
| `test/e2e/overview.spec.js` | Numbers that survive an empty database. The predecessor hardcoded 15.4K and 99.2% and looked entirely convincing; these read §1.3's figures out of Firestore and assert the empty state stays empty. |

```bash
flutter test                 # 481 unit and widget tests
tool/test_rules.sh           # 74 security rules tests, on the emulator
tool/test_e2e.sh             # 8 browser tests against the dashboard
flutter build apk && flutter build ios && flutter build web
```

`tool/test_rules.sh` and `tool/test_e2e.sh` need no Firebase project and no
network — they run against the emulators with a demo project id. Both need a
JDK 21+; they point themselves at a Homebrew `openjdk@21` if your default
`java` is older.

`tool/test_e2e.sh` builds the web app with `--dart-define=USE_EMULATOR=true`,
which points it at the local emulators **and** turns on Flutter's accessibility
tree at boot. Both matter: Flutter web paints to a canvas, so that tree is the
only thing a browser can read, and the tests therefore reach the dashboard
through the same surface a screen reader uses. It leaves `build/web` pointed at
the emulators, so run a plain `flutter build web` before deploying.

A Playwright MCP server is declared in `.mcp.json` for driving the dashboard
interactively while writing these tests. It is a convenience for that, not a
dependency: `tool/test_e2e.sh` runs standalone.

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
