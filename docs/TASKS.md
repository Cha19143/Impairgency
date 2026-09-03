# Tasks

Working checklist for [`BUILD_PLAN.md`](BUILD_PLAN.md). The plan explains *why*;
this is *what*, in order.

**Conventions**

- `[x]` done and verified. `[ ]` not started. `[~]` in progress.
- **Blocked by** means it genuinely cannot be built first, not that it is merely
  scheduled later.
- Every item names the requirements-document section it answers, so an item that
  cannot cite one is scope creep and should be argued for before it is built.
- Phase gates at the end of each phase are not optional. A phase is not done
  because its boxes are ticked; it is done when its gate passes.

**This file is the source of truth.** It is offline, versioned, and reviewable in
a diff. [GitHub Issues](https://github.com/calmadex/impairgency/issues) mirror it
— 68 issues, one milestone per phase — but the mirror is one-way:
`tool/seed_issues.py` seeded it once and does not sync. When you finish something,
tick it here, close the issue there, and run `python3 tool/progress.py`.

<!-- PROGRESS -->

| Phase | | Done |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **36 / 85  (42%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `█████████░░░` | 5 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **34 / 85  (40%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `█████████░░░` | 5 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **34 / 85  (40%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `█████░░░░░░░` | 3 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **32 / 85  (38%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **29 / 85  (34%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `█████████░░░` | 9 / 12 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **28 / 85  (33%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `█████████░░░` | 8 / 11 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **27 / 84  (32%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `█████████░░░` | 8 / 11 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **27 / 84  (32%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `█████░░░░░░░` | 4 / 9 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **23 / 82  (28%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `████░░░░░░░░` | 3 / 9 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **22 / 82  (27%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `███░░░░░░░░░` | 2 / 9 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **21 / 82  (26%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `░░░░░░░░░░░░` | 0 / 9 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **19 / 82  (23%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `██████████░░` | 15 / 18 |
| Phase 1 — Location, push, pairing `M` | `░░░░░░░░░░░░` | 0 / 9 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **16 / 81  (20%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `████░░░░░░░░` | 6 / 18 |
| Phase 1 — Location, push, pairing `M` | `░░░░░░░░░░░░` | 0 / 9 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **7 / 81  (9%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███░░░░░░░░░` | 5 / 18 |
| Phase 1 — Location, push, pairing `M` | `░░░░░░░░░░░░` | 0 / 9 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **6 / 81  (7%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███░░░░░░░░░` | 5 / 18 |
| Phase 1 — Location, push, pairing `M` | `░░░░░░░░░░░░` | 0 / 9 |
| Phase 2 — Location history and aggregations `M` | `░░░░░░░░░░░░` | 0 / 7 |
| Phase 3 — Web dashboard `M` | `░░░░░░░░░░░░` | 0 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **6 / 81  (7%)** |


---

## Phase 0 — Security and integrity `S`

Blocking. Nothing else should store data until this is deployed.

- [x] `firestore.rules` written and committed — guardian access via accepted
      pairing only, location reads additionally gated on consent, admin as a
      custom claim, `otp_verification` unreachable from any client, default deny
- [x] `storage.rules` — owner-only, size-capped, no public-read match
- [x] `firebase.json` — `firestore`, `storage`, `functions`, `hosting`, emulators
- [x] Router redirect: platform split + auth guard (`lib/app/routes.dart`)
- [x] Contrast defect fixed **and asserted** (`test/core/contrast_test.dart`) — §4
- [x] Safety notice — spoken on first run, reachable afterwards — §7
      *"AI guidance should assist users but should not guarantee that an
      environment is completely safe."*
- [x] `flutterfire configure` — project `impairgency-capstone`, one app `ph.impairgency.app` across android/ios/web
- [x] `Firebase.initializeApp` wired in `lib/main.dart`
- [x] `firebase deploy --only firestore:rules` — live on `impairgency-capstone`
- [ ] `firebase deploy --only storage` — blocked: Storage is not provisioned on the
      project yet (Console → Storage → Get Started). Nothing in scope needs it;
      recording is the substituted item, so this can wait for Phase 2 at the earliest
- [x] Rules tests on the emulator — `tool/test_rules.sh`, 28 passing
  - [x] owner reads and writes own document
  - [x] guardian reads a paired user
  - [x] guardian is refused an unpaired user
  - [x] guardian is refused location fixes when consent is off
  - [x] client is refused `otp_verification` entirely
  - [x] a client cannot set its own `role` or `admin`
  - [x] a pairing code cannot be redeemed twice
  - [x] an expired pairing code is refused

**Gate:** rules deployed, emulator suite green, `flutter test` green.

---

## Phase 1 — Location, push, pairing `M`

*Blocked by: Phase 0 (Firebase configured).* De-risked early because native
configuration is what bites late.

- [x] Platform permission strings — `Info.plist` (5 purpose strings), `AndroidManifest.xml`
      (location, notifications, camera, mic, contacts, plus the `tel:` intent query
      without which the SOS call leg silently fails on API 30+)
- [x] `lib/core/location/` — fix type, source interface, and the decision policy
      as a pure function. Foreground only; background needs a Play justification
      the project does not have — §2.A.4
- [x] Debug screen proving a real fix on a real device — verified on an iPhone
      (iOS 26.6): permission → ready, GNSS fix at ±11 m, `trust: fresh`, and the
      local alert delivered. Debug builds only
- [x] Android `IMPORTANCE_HIGH` channel declared — `impairgency_emergency`
- [ ] ~~APNs key~~ — **won't do**: needs a $99/year Apple Developer Program
      membership. Android is the demo platform; declared on the scope table
- [x] `firebase_messaging` token registration and refresh, with owner-only
      rules and dead-token pruning
- [x] Cloud Function written — SOS write → high-priority fan-out to paired
      guardian tokens, per-token outcomes recorded on the event
- [x] Free replacement shipped — guardian-side Firestore listener raising a
      local notification (`SosWatcher`, `LocalAlertPresenter`). The Function
      stays as the production path for when a billing account exists
- [ ] ~~Deploy the Function~~ — **won't do**: needs the Blaze plan, and the
      project is staying free
- [x] Documented fallback — [`EMERGENCY_DELIVERY.md`](EMERGENCY_DELIVERY.md),
      every leg and every way it fails — §7 reliability
- [x] `pairing_codes` write + redeem repository — single-use, expiring, with a
      speak-safe alphabet, and an end-to-end rules test of the whole flow
- [x] Guardian **Accept invitation** screen — §3, wired into the router

**Gate:** a real push lands on a second physical device from a real SOS write,
in **release** mode, not debug.

---

## Phase 2 — Location history and aggregations `M`

*Blocked by: Phase 1 (location).* Can run alongside Phase 4.

- [x] `location_history/{userId}/fixes/{fixId}` writer, gated server-side on a
      **separate** `consent.history` — sharing location and being recorded are
      two different questions. Append-only, 60-day retention, always deletable
- [x] Stay-point detection then centroid-linkage clustering → places — §2.B.2.
      Never invents a name; the user labels them or nobody does
- [x] Median arrival/departure with a spread gate, plus weekday/weekend
      patterns — §2.B.1. Refuses to claim a typical time it cannot support
- [x] Session path replay — §2.A.7. Drops readings implying over 200 km/h and
      accuracies worse than 200 m, and reports how many it threw away
- [x] Frequent-locations count aggregation — §1.3, `frequentPlaces` ordered
      most-visited first, one visit not counted as a frequency
- [x] Session event log — obstacles, stairs, text read, SOS armed/fired/
      cancelled — same consent and retention as the fixes, owner and admin
      only. A guardian is deliberately not given a feed of what the user
      walked past
- [x] **Event timeline** replacing video review — §1.1. Stamped against the
      session start, and it surfaces **concerns** rather than only events:
      cancelled SOS, repeated stairs warnings, poor positioning, a session
      that never moved. That is what "identify possible system improvements"
      is actually asking for

**Gate:** one recorded walk produces a named place, a schedule bucket, a
replayable path and a timeline — from the same collection.

---

## Phase 3 — Web dashboard `M`

*Blocked by: Phase 2 for real numbers.* The shell can be built in parallel;
just do not populate it with fabricated figures.

- [ ] Firebase Hosting target + `flutter build web` deploy step
- [ ] Admin sign-in; custom claim set by a Cloud Function, never by a client
- [ ] **Overview** — all five metrics §1.3 names:
  - [ ] active users
  - [ ] navigation sessions
  - [ ] SOS incidents
  - [ ] frequently visited locations
  - [ ] detection performance
- [ ] **Users** — VI users, guardians, **admin accounts**, device links — §1.2
- [ ] Add-user form gains email and role; Device ID becomes optional
- [ ] **System health** — read `firebase_performance`, add Crashlytics — §1.4
- [ ] Rename *Accessibility Audits* → *Accessibility Results*, wired to real
      test output

**Gate:** the deployed URL shows only the dashboard; a mobile build cannot reach
it; a signed-in non-admin cannot reach it.

---

## Phase 4 — Flow, SOS, voice `L`

*Blocked by: Phase 1 for consent and pairing to mean anything.*

**Onboarding** — account first, so the flow stops being circular

- [ ] Welcome — speaks on launch, two doors
- [ ] Create account — **credentials never dictated**; voice moves between
      fields, the keyboard enters them
- [ ] How you'll use it — screen-on preference; derives the admin category
- [ ] Emergency contact — skippable, and skipping says what SOS then cannot do
- [ ] Invite a guardian — pairing code
- [ ] Consent — location, recording, faces; **all off by default** — §7
- [ ] Device — last and optional, gating nothing — §5
- [ ] All set — one action, and **no route back to sign-in**

**SOS**

- [ ] Arming countdown before anything dials — §7 reliability
- [ ] Cancel keywords wired to the countdown (`kCancellationCommands`)
- [ ] Receipt naming every leg's outcome, spoken and shown
- [ ] Failed legs named as failed, never implied as success

**Voice** — the parser and its tests already exist; these are the handlers

- [ ] `whereAmI` handler — §2.C
- [ ] `callGuardian` handler — §2.C
- [ ] `connectDevice` handler — §2.C, honest about §5 being out of scope
- [ ] "What can I say?" screen, generated from `kCommandDescriptions`

**Other**

- [ ] Repeat button on Scan
- [ ] Consent centre — inspect and revoke, revocation enforced server-side
- [ ] What the app has learned — list and delete, backed by Phase 2
- [ ] Device connect reachable from settings, not only onboarding — §5
- [ ] **Offline-tolerant first run** — cached credential so a returning user
      still reaches the dashboard with alarm and dialler live

**Gate:** all of onboarding completed with VoiceOver on and **Screen Curtain
enabled**. Screen fully black, start to finish.

---

## Phase 5 — Accessibility, docs, defense `S`

- [ ] Widget test per screen: every control has a semantic label
- [ ] No overflow at 2.0× text scale, every screen
- [ ] Flow test: setup resumes at the first incomplete step after a kill
- [ ] `flutter build apk && flutter build ios && flutter build web`
- [ ] Skip every skippable step; confirm SOS still works
- [ ] SOS with no contact and no guardian — receipt must say nobody was reached
- [ ] Revoke location consent, confirm the **server** denies the read
- [ ] Airplane mode, signed-in user: dashboard, alarm, dialler still up
- [ ] Demo script with a network-failure path
- [ ] Scope table on a slide, unedited

**Gate:** someone who has never used the app completes onboarding blind.

---

## Port from `cprwire` — do not rewrite these

The old repo at `~/kokey/CapstoneImpairgency/cprwire/` is reference-only.

- [ ] Camera + detection loop from `scan_environment_widget.dart` — without its
      FlutterFlow scaffolding. **Note:** `camera`, `google_mlkit_object_detection`,
      `tflite_flutter` and `image` are deliberately not declared yet — ML Kit
      ships no arm64 simulator slice and breaks every iOS simulator build. Add
      them back with this, and verify on a physical device (a simulator has no
      camera anyway)
- [ ] Contact picker. **Do not use `flutter_contacts`** — its iOS registration
      force-unwraps `UIApplication.shared.delegate!.window!!`, which has been nil
      since iOS 13, so it crashes on launch in any app that includes it. Prefer
      the system picker (`CNContactPickerViewController` / `ACTION_PICK`), which
      needs no contacts permission at all
- [ ] OTP Cloud Functions from `firebase/functions/`
- [x] Voice command vocabulary + tests — *ported and extended to six commands*

---

## Out of scope — do not build

Declared in the documentation with reasons. If one of these gets built anyway,
the reason it was scoped out was wrong — argue that first, in writing.

- [ ] ~~Familiar person recognition~~ — §2.A.6, §2.B.3 — third-party biometrics
      with no consent mechanism
- [ ] ~~Bluetooth / IoT hardware~~ — §5 — no device exists to pair with
- [ ] ~~Fire and emergency exit guidance~~ — §2.A.2 — needs indoor floor plans
- [ ] ~~Video session recording~~ — §1.1 — substituted by the Phase 2 timeline

Partial, and worth attempting: **stairs detection** (§2.A.3). It is a fall risk.
A dedicated class or a floor-plane heuristic, with a confidence threshold that
stays silent rather than guessing.
