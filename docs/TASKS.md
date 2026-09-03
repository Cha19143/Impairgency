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
- [ ] `flutterfire configure` against the new Firebase project
- [ ] Uncomment `Firebase.initializeApp` in `lib/main.dart`
- [ ] `firebase deploy --only firestore:rules,storage:rules`
- [ ] Rules tests on the emulator:
  - [ ] owner reads and writes own document
  - [ ] guardian reads a paired user
  - [ ] guardian is refused an unpaired user
  - [ ] guardian is refused location fixes when consent is off
  - [ ] client is refused `otp_verification` entirely
  - [ ] a client cannot set its own `role` or `admin`
  - [ ] a pairing code cannot be redeemed twice
  - [ ] an expired pairing code is refused

**Gate:** rules deployed, emulator suite green, `flutter test` green.

---

## Phase 1 — Location, push, pairing `M`

*Blocked by: Phase 0 (Firebase configured).* De-risked early because native
configuration is what bites late.

- [ ] Add `geolocator` permission strings — `Info.plist`, `AndroidManifest.xml`
- [ ] `LocationService` in `lib/core/location/` — foreground fixes, permission
      state, graceful denial — §2.A.4
- [ ] Throwaway debug screen proving a real fix on a real device
- [ ] APNs key uploaded; Android `IMPORTANCE_HIGH` notification channel — §3.2
- [ ] `firebase_messaging` token registration and refresh
- [ ] Cloud Function: SOS write → high-priority message to paired guardian tokens
- [ ] Documented fallback when critical alerts are unavailable — §7 reliability
- [ ] `pairing_codes` write + redeem repository — single-use, expiring
- [ ] Guardian **Accept invitation** screen — §3

**Gate:** a real push lands on a second physical device from a real SOS write,
in **release** mode, not debug.

---

## Phase 2 — Location history and aggregations `M`

*Blocked by: Phase 1 (location).* Can run alongside Phase 4.

- [ ] `location_history/{userId}/fixes/{fixId}` writer, consent-gated
- [ ] Proximity clustering → named places — §2.B.2 environment learning
- [ ] Hour/weekday buckets over clusters — §2.B.1 routine learning
- [ ] Session path replay — §2.A.7 travel recording
- [ ] Frequent-locations count aggregation — §1.3
- [ ] Detection + SOS event log, stamped against the session path
- [ ] **Event timeline** replacing video review — §1.1, and record the
      substitution in the documentation rather than leaving §1.1 looking unmet

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
      FlutterFlow scaffolding
- [ ] Contact picker
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
