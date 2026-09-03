# ImpairGency — Build Plan

Scoped against `DOCUMENTATION_SUMMARY` (the requirements document), not `ui.pdf`.

This replaces the earlier user-flow plan. That document was written against the UI
design, which is a subset of the requirements with additions of its own, so it
optimised a flow that was already drawn and never noticed the features nobody had
drawn at all. Its file list also described a repository that does not exist. Both
are corrected here; see [Corrections](#corrections-to-the-previous-plan) at the end.

---

## Where the project actually stands

One FlutterFlow app at `cprwire/`, 25 screens, Firebase backend, `main` branch.

**Works, and is worth defending:**
- On-device object detection — `google_mlkit_object_detection` + `tflite_flutter`
  in `lib/main/scan_environment/`. Speaks what it sees.
- Voice command parsing — `lib/backend/voice_command_service.dart`, 8 tests, all green.
- Email/OTP registration, contact picker, Firestore user records.
- The three-button dashboard. Large targets, short vocabulary, no clutter.

**Mocked — looks finished, has nothing behind it:**
- `guardian_location` displays the literal string `123 st Wakas Bocaue` and
  `Last Updated: 1 min ago`.
- `analytics` hardcodes `15.4K`, `99.2%`, `14ms`.
- `register3` invents a device ID from an `app_counters` document. There is no radio.

**Absent — no dependency, no code, no screen:**

| Requirement | Doc | Missing dependency |
|---|---|---|
| Real-time location sharing | §2.A.4, §2.A.5, §3.1 | no `geolocator` / `location` |
| Guardian SOS push alerts | §3.2 | no `firebase_messaging` |
| Bluetooth device pairing | §5 | no BLE package |
| Session recording + admin review | §1.1 | no `firebase_storage`, no video capture |
| System performance monitoring | §1.4 | `firebase_performance` *is* installed and unread |
| IoT device management | §1.5 | — |
| Web delivery of the admin dashboard | Overview, §6 | `isWeb` exists, no route uses it |

**Not previously reported, and more urgent than any of the above:**

- **There is no `firestore.rules` in this repository.** `git ls-files` returns only
  `storage.rules`. The app stores emergency contacts, guardian links and
  impairment type in `users`, and one-time login codes in `otp_verification`.
  Whatever rules protect them were set in the Firebase console, are not version
  controlled, and nobody on the team can review them. If the project was started in
  test mode, those rules read `allow read, write: if true` and **expire 30 days
  after creation**, at which point the app stops working — classically, during a
  demo. Verify before anything else:

  ```bash
  firebase firestore:rules:get --project cprwire-igjnyu
  ```

- **`firebase.json` declares no `firestore`, `storage` or `hosting` targets.** Rules
  cannot be deployed from this repo, and the web dashboard has nowhere to deploy to.

- **The router has no auth guard.** `nav.dart` sets `initialLocation: '/'` and
  registers `/adminDashboard`, `/userManagement` and `/analytics` as plain routes
  with no redirect. On mobile that needs a rooted device to reach. On web — which
  the requirements document asks for — it is a URL.

- **`storage.rules` grants public read.** `match /{allPaths=**} { allow read, write: if false; }`
  followed by `match /users/{userId}/{allPaths=**} { allow read: if true; }`. Firebase
  evaluates every matching rule and grants on any allow, so `/users/**` is world-readable
  today. If session recordings ever land there, they are public.

---

## The scoping principle

This is a capstone, not a funded product. The requirements document names roughly
thirty features across three platforms. A student team cannot build all of them, and
a panel knows that.

**A defended scope boundary scores; an undefended feature claim does not.** A panel
that hears "we scoped out face recognition because we could not obtain consent from
the third parties whose biometrics it would process" reads competence. A panel that
sees a *Familiar People* menu item that opens an empty screen reads the opposite.

So every requirement below lands in one of four places, and the fourth is written
into the documentation rather than hidden:

1. **Build** — the project is not defensible without it.
2. **Build cheaply** — small, and it makes a demo visibly better.
3. **Substitute** — deliver the requirement's stated *purpose* by a simpler means,
   and say so.
4. **Declare out of scope** — with the reason, in the documentation.

---

## Phase 0 — Security and integrity

Blocking. Small. Everything else writes data that these rules protect.

1. **Write `cprwire/firebase/firestore.rules` and commit it.** A user document is
   readable and writable by its owner; a guardian reads only the users who have
   accepted their pairing; admins are identified by a custom claim, never by a
   field the client can write. `otp_verification` is **writable by nobody from the
   client** — codes are issued and checked in `firebase/functions/`, because a
   collection of live login codes that any authenticated session can read is an
   account takeover.
2. **Fix `storage.rules`.** Remove the public-read match. Owner-only.
3. **Add `firestore`, `storage` and `hosting` to `firebase.json`** so rules are
   deployable from the repo and the web build has a target.
4. **Add a `redirect` to `createRouter`.** Signed out → HomePage. Signed in without
   completed setup → resume onboarding. Admin routes require the admin claim. This
   is one function and it closes the URL hole before the web build exists.
5. **Fix the contrast defect.** The cyan buttons set their label to
   `FlutterFlowTheme.of(context).secondaryBackground`, which is `#FFFFFF` in the
   light theme — white on `#00FFFF`, about **1.1:1**. Requirements §4 asks for high
   contrast in as many words. Use a fixed dark ink on cyan. It is a one-line change
   in each of `main_dashboard`, `scan_environment` and the register screens.
6. **Add the safety notice.** §7: *"AI guidance should assist users but should not
   guarantee that an environment is completely safe."* Spoken once on first run,
   and reachable afterwards from the dashboard. One screen. It is also the sentence
   that justifies every scoping decision below.

*Verification: rules unit tests via the emulator — owner reads own doc, guardian
reads paired user only, guardian cannot read an unpaired user, client cannot read
`otp_verification`, anonymous cannot reach `/adminDashboard`.*

---

## Phase 1 — The three capabilities that make the product real

De-risked early on purpose. All three need native configuration (`Info.plist`,
`AndroidManifest.xml`, APNs), and native configuration is what bites late.

1. **Location — `geolocator`.** Foreground permission first; background only if the
   demo needs it. This single dependency unblocks four requirements: the SOS location
   leg (§2.A.5), guardian tracking (§3.1), the learning collapse in Phase 2, and the
   admin dashboard's frequently-visited-locations panel (§1.3).
2. **Push — `firebase_messaging` + a Cloud Function trigger.** When an SOS document
   is written, the function sends a high-priority data message to every paired
   guardian token. §3.2 asks for immediate delivery with vibration; on Android that
   means an `IMPORTANCE_HIGH` notification channel, on iOS an APNs key and the
   critical-alert path if the account allows it, and a documented fallback if not.
3. **A `pairing_codes` collection.** Single-use, expiring, readable by any signed-in
   user, writable only by the owner. This is the only thing standing between the
   guardian app and being unreachable.

Prove all three end-to-end behind a throwaway debug screen before wiring them into
real UI. If APNs is going to fight, find out in week two rather than week eight.

---

## Phase 2 — One collection, four requirements

The requirements document asks for routine learning (§2.B.1), environment learning
(§2.B.2), travel recording (§2.A.7) and frequently visited locations (§1.3). Read
together, those four are not four machine-learning problems. They are **aggregations
over one collection of timestamped location fixes.**

```
location_history/{userId}/fixes/{fixId}
  { lat, lng, accuracy, at, placeId?, sessionId }
```

- **Environment learning** = cluster fixes by proximity, name the top clusters, let
  the user label them. Home, school, workplace — the exact examples §2.B.2 gives.
- **Routine learning** = the same clusters bucketed by hour and weekday. "You usually
  leave home around 7:30." §2.B.1 asks for destinations, routes and schedules.
- **Travel recording** = the fixes for one session, replayable as a path. §2.A.7.
- **Frequently visited locations** = a `count` aggregation, straight into the admin
  dashboard. §1.3.

No model training, no labelled data, nothing that cannot be explained in one slide.
It is honest about what it is — the app says *"places you go often"*, not *"the AI has
learned your routine"* — and it is the difference between three requirements marked
*future work* and three requirements marked *done*.

It also feeds Phase 3, which is why it comes first.

**The one substitution worth making explicit.** §1.1 asks admins to review recorded
sessions in order to *"analyse navigation performance and identify possible system
improvements."* That is the stated purpose; video is the stated means. Deliver the
purpose with an **event timeline** instead — obstacle detected, stairs detected, SOS
fired, route learned, each stamped against the session path from this same collection.
It answers the question the requirement is actually asking, costs no storage, and
carries none of the consent burden of recording a blind person's home. Video review
stays as declared future work.

---

## Phase 3 — The web dashboard

The requirements document opens by naming three platforms and the first is
**Admin Dashboard (Web)**. It is currently five mobile pages in the same router as
the blind user's app.

**Do not build a second front end.** One Flutter codebase, split at the entry point:

```dart
// nav.dart
initialLocation: kIsWeb ? '/admin' : '/',
redirect: (context, state) {
  if (kIsWeb && !state.matchedLocation.startsWith('/admin')) return '/admin';
  if (!kIsWeb && state.matchedLocation.startsWith('/admin')) return '/';
  // ... auth guard from Phase 0
}
```

`flutter build web` then produces the admin dashboard and only the admin dashboard,
deployed to Firebase Hosting. The mobile builds are unchanged. This is roughly a day
of routing work versus weeks for a separate React app, and §6 explicitly anticipates
it: *"Flutter can potentially be used to develop… web-based Admin Dashboard."*

Three screens, laid out in the mockup:

- **Overview** — all five metrics §1.3 names. Active users and sessions exist today;
  SOS incidents, frequently visited locations and detection performance come from
  Phase 2.
- **Users** — extend `user_management`, which already handles VI users and guardians.
  Add admin accounts and device links (§1.2). `adminadduser` gains email and role;
  Device ID becomes optional.
- **System health** — errors, crashes, response times, status (§1.4). **This is nearly
  free**: `firebase_performance` is already in `pubspec.yaml` and nothing reads it.
  Add `firebase_crashlytics` and read both.

Rename **Accessibility Audits** to **Accessibility Results** and point it at the real
`flutter test` accessibility output. It is not a requirement — it came from `ui.pdf` —
but a button that audits nothing is worse than no button.

---

## Phase 4 — The flow rework, on top of real capabilities

This is the previous plan, and it was right about the flow. It is fourth rather than
first because its consent screen now switches a permission that exists and its
guardian invite now redeems a code that exists.

Account first, reordered so it is not circular: **Welcome → Create account → How
you'll use it → Emergency contact → Invite a guardian → Consent → Device → All set.**
Steps 3, 5 and 7 skippable, and skipping says plainly what it costs.

`home_page` already carries *"Welcome to ImpairGency / LOGIN / REGISTER"*, so Welcome
is a revision of an existing screen, not a new one. Registration moves from step 5/5 to
step 1. **Credentials are never dictated** — voice moves between fields, the keyboard
enters them. `GO TO LOGIN` comes off the completion screen.

Also in this phase:

- **SOS arming countdown** before anything dials, so Cancel is real. Requires cancel
  keywords, which do not exist in `kVoiceKeywords` at all today — English and
  Filipino both (`cancel`, `stop`, `teka`, `tigil`, `sandali`, `hindi`).
- **SOS receipt** naming every leg's outcome, spoken and shown. With Phase 1 done,
  the location and guardian legs are real rather than aspirational.
- **Voice commands 4–6.** §2.C names six functions; `VoiceCommand` implements three.
  Add `whereAmI`, `callGuardian`, `connectDevice`. The parser and its tests already
  exist — this is a keyword list and three handlers.
- **"What can I say?"** — the vocabulary screen ten microphone icons imply.
- **Repeat** on Scan. Documented in `ui.pdf`, never built, genuinely good.
- **Consent centre** and **What the app has learned**, now backed by Phase 2 data.
- **Offline-tolerant first run** — a cached credential so a previously signed-in user
  reaches the dashboard with the alarm and dialler live. Account-first means an
  unregistered phone with no network is a phone with no SOS. Not optional.

---

## Declared out of scope

Written into the documentation as future work, each with its reason. All four are
defensible under §7's own framing.

| Requirement | Why not |
|---|---|
| **Familiar person recognition** (§2.A.6, §2.B.3) | It processes the biometrics of third parties who are never asked. §7 requires consent for recognition of people, and there is no mechanism by which a stranger on the street could give it. Scoping this out is the ethically correct answer, not merely the convenient one. |
| **Bluetooth / IoT hardware** (§5) | No device exists to pair with. A BLE stack written against imaginary hardware is untestable code. The architecture keeps hardware gating nothing, so it can be added later without touching the flow. |
| **Emergency and fire exit guidance** (§2.A.2) | Requires indoor floor-plan data. No public source provides it for the buildings these users occupy. Naming this honestly is better than a feature that silently never fires. |
| **Video session recording** (§1.1) | Substituted by the event timeline in Phase 2, which serves the requirement's stated purpose. Full video review remains future work: it is the highest-consent-burden feature in the document and the one whose storage rules are currently broken. |

Stairs, walls and door detection (§2.A.3) sit between build and substitute. Generic
object detection covers some of it. **Stairs specifically is a fall risk and should be
attempted** — a dedicated class, or a floor-plane heuristic, and an honest confidence
threshold that stays silent rather than guessing.

---

## Sequence

Sized in relative effort, not dates — set the calendar against your defense date.

| # | Phase | Size | Unblocks |
|---|---|---|---|
| 0 | Security and integrity | S | everything; do not skip |
| 1 | Location, push, pairing codes | M | SOS, guardian app, Phase 2 |
| 2 | `location_history` + aggregations | M | Phase 3 metrics, learning requirements |
| 3 | Web dashboard + hosting | M | the third platform |
| 4 | Flow rework, SOS, voice | L | the demo |
| 5 | Accessibility pass, docs, demo script | S | the defense |

Phases 2 and 3 can run in parallel with 4 if the team splits; nothing in 4 depends on
them except the two screens that read learned data.

---

## Verification

**Automated**
- `flutter test` — 8 voice tests green today; extend for the three new commands and
  the cancel keywords.
- Firestore rules tests on the emulator, per Phase 0.
- Widget tests per onboarding screen: every control carries a semantic label, and no
  overflow at 2.0× text scale.
- A flow test asserting setup resumes at the first incomplete step after a kill.
- `flutter build apk`, `flutter build ios`, `flutter build web` — all three. Defects
  this project has already hit were invisible to `analyze` and `test`.

**Manual, on device**
- Complete the whole of onboarding with **VoiceOver on and Screen Curtain enabled** —
  screen fully black. Anything that cannot be finished this way is a defect, and this
  is the test §4 is actually asking for.
- Skip every skippable step; confirm the app still reaches a working SOS.
- Fire SOS with no contact and no guardian; confirm the receipt says nobody was
  reached rather than implying success.
- Revoke location consent, then confirm the server denies the read.
- Put the phone in airplane mode and open the app as a signed-in user. The dashboard,
  alarm and dialler must still come up.

**For the defense**
- A written demo script with a network-failure path.
- The scope table above, on a slide, unedited.

---

## Risks

- **Firestore rules are unknown and unversioned.** If they are in test mode they
  expire, and the app dies on whatever day that falls. Highest-severity item in this
  document and the cheapest to resolve.
- **Account-first means no network is no SOS** until the offline mitigation in Phase 4
  lands. If the defense venue has poor signal, that is the failure the panel sees.
- **APNs configuration** is the most common cause of a push feature that works in
  debug and not in release. Phase 1 exists to surface that early.
- **Scope creep back toward `ui.pdf`.** The design contains features the requirements
  do not (guardian video call, Accessibility Audits). Building them costs weeks and
  earns nothing, because the panel grades against the requirements document.

---

## Corrections to the previous plan

For anyone reading both documents:

- Its file list — `apps/vi_app/`, `packages/impairgency_core/`, `SosEngine`,
  `SpeechQueue`, `HazardPolicy`, "105 tests" — describes a repository that does not
  exist. This project is one FlutterFlow app at `cprwire/` with two test files.
- "One failing test is currently red" is false. All 8 tests in
  `test/voice_command_test.dart` pass.
- The Filipino cancel keywords did not "fail to land" in a file — there are no cancel
  keywords in `kVoiceKeywords` at all, in any language.
- "Nothing is skippable" is wrong: `register4` already offers **Skip for Now**. The
  real defect is that skipping is silent about what SOS then cannot do.
- Welcome is not a new screen. `home_page` already exists and carries that content.
- It treats `SosEngine` and friends as "already built, keep as-is." None of it exists.

The flow analysis in that document is sound and is preserved in Phase 4. The scope,
sequence and file list are replaced by this one.
