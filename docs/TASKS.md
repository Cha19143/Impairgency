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
| Phase 0 — Security and integrity `S` | `████████████` | 19 / 19 |
| Phase 1 — Location, push, pairing `M` | `████████████` | 10 / 10 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 21 / 21 |
| Phase 4 — Flow, SOS, voice `L` | `████████████` | 21 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `████████████` | 10 / 10 |
| Port from `cprwire` — do not rewrite these | `████████████` | 4 / 4 |
| Tester feedback round — one tester, one device, thirteen items | `████████████` | 13 / 13 |
| Tester feedback round 2 — September 15 | `███████████░` | 36 / 38 |
| Tester feedback round 3 — September 16 | `██████████░░` | 26 / 30 |
| Tester feedback round 4 — September 18 | `█████████░░░` | 26 / 36 |
| **Overall** | | **193 / 209  (92%)** |
---

## Phase 0 — Security and integrity `S`

Blocking. Nothing else should store data until this is deployed.

- [x] `firestore.rules` written and committed — guardian access via accepted
      pairing only, location reads additionally gated on consent, admin as a
      custom claim, `otp_verification` unreachable from any client, default deny
- [x] `storage.rules` — owner-only, size-capped, no public-read match, and
      **proved on the emulator**. Writing the tests found a live defect: the
      size cap sat on a combined `read, write` allow, but `request.resource`
      is null on reads and deletes, so the owner was locked out of their own
      files. Split by operation and asserted
- [x] `firebase.json` — `firestore`, `storage`, `functions`, `hosting`, emulators
- [x] Router redirect: platform split + auth guard (`lib/app/routes.dart`)
- [x] Contrast defect fixed **and asserted** (`test/core/contrast_test.dart`) — §4
- [x] Safety notice — spoken on first run, reachable afterwards — §7
      *"AI guidance should assist users but should not guarantee that an
      environment is completely safe."*
- [x] `flutterfire configure` — project `impairgency-capstone`, one app `ph.impairgency.app` across android/ios/web
- [x] `Firebase.initializeApp` wired in `lib/main.dart`
- [x] `firebase deploy --only firestore:rules` — live on `impairgency-capstone`
- [x] `firebase deploy --only storage` — **not blocked. Out of scope, on purpose.**
      A Cloud Storage bucket requires the **Blaze plan**, which this project has
      no budget for. This was previously recorded as "needs a location chosen in
      the console"; that was wrong, and it mattered, because it framed a hard
      budget boundary as thirty seconds of clicking. These rules cannot be
      deployed on this project at all. They are *proved* instead, on the Storage
      emulator, which provisions a local bucket for free — see
      `test/rules/storage.test.js`. Nothing in scope stores a file; recording is
      the substituted item. Defended in `docs/SCOPE.md`
- [x] Rules tests on the emulator — `tool/test_rules.sh`, 74 passing (64 Firestore, 10 Storage)
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

**Gate:** ✅ **passed** — `test/core/places/phase2_gate_test.dart` feeds a
fortnight of one plausible life into the fixes collection and gets all four
back out: two places, a schedule described in local time, a 4 km replayable
path, and a review timeline. Asserted rather than claimed.

---

## Phase 3 — Web dashboard `M`

*Blocked by: Phase 2 for real numbers.* The shell can be built in parallel;
just do not populate it with fabricated figures.

- [x] Firebase Hosting — **live at https://impairgency-capstone.web.app**.
      Free on Spark; `firebase deploy --only hosting` after `flutter build web`
- [x] Admin sign-in, gated on the `admins` collection rather than a custom
      claim — same property, no billing account. Verified live: an
      unauthenticated visit to the site lands on sign-in, not the app
- [x] **Overview** — all five metrics §1.3 names, from `session_summaries`:
  - [x] active users
  - [x] navigation sessions
  - [x] SOS incidents
  - [x] frequently visited locations — counted from names *users typed*; the
        summaries carry no coordinates, enforced in the rules
  - [x] detection performance — counts and positioning quality, with the
        caveat printed on screen that counts are not accuracy
- [x] **Users** — VI users, guardians, admin accounts, device links — §1.2.
      Admin status comes from the roster, not a field on the user document
- [x] Add-user replaced by an **invitation**: email and role in, Device ID
      optional, and **no password field at all**. Creating the auth account
      here would mean a server or an admin choosing someone else's password
      and signing themselves out doing it. The invited person registers
      themselves and picks the role up on the way in
- [x] **System health** — §1.4, split honestly. Positioning quality, flagged
      sessions and emergencies are measured from real data; crashes and
      response times are **linked to the console rather than mirrored**,
      because reading them back needs a service account and therefore a
      paid plan. A made-up crash-free percentage would repeat exactly the
      defect this dashboard exists to fix
- [x] *Accessibility Audits* → **Accessibility results**, showing the measured
      contrast of every pair the app renders, computed live from the same
      constant the app paints with and the tests assert against. All eight
      pass AA; the three large action buttons clear AAA

- [x] Browser tests on the emulators — `tool/test_e2e.sh`, 8 passing. Playwright
      drives the shipped web build through Flutter's accessibility tree, which
      is the only DOM a canvas-rendered app exposes and the same surface a
      screen reader uses
  - [x] a signed-out deep link into the dashboard lands on sign-in
  - [x] the mobile app is not reachable on the web build
  - [x] a wrong password says so, and does not pretend to sign in
  - [x] an administrator signs in and lands on the overview
  - [x] the overview reports the seeded sessions, not a placeholder
  - [x] an empty database says so, instead of showing zeroes
  - [x] a non-admin is told why they cannot get in. Found by this suite:
        authentication succeeded and nothing happened, because the redirect
        correctly returned null and go_router did not rebuild the route. The
        route now rebuilds from the session, and the spec is an ordinary test
  - [x] an administrator can open every sidebar section (round 3)

**Gate:** the deployed URL shows only the dashboard; a mobile build cannot reach
it; a signed-in non-admin cannot reach it.

---

## Phase 4 — Flow, SOS, voice `L`

*Blocked by: Phase 1 for consent and pairing to mean anything.*

**Onboarding** — account first, so the flow stops being circular

- [x] Welcome — speaks on launch, two doors
- [x] Create account — **credentials never dictated**; voice moves between
      fields, the keyboard enters them. Moved from step 5/5 to step 1/6
- [x] How you'll use it — screen-on preference; derives the admin category
- [x] Emergency contact — skippable, and the first tap on Skip **explains
      before it does**, spoken as well as shown
- [x] Invite a guardian — pairing code, spelled out character by character
      rather than read as a word
- [x] Consent — location, history, recording, faces; **all off by default**,
      each saying who can see the result — §7
- [x] Device — last and optional, gating nothing — §5
- [x] All set — one action, **no route back to sign-in**, and it says what is
      *missing* rather than congratulating

**SOS**

- [x] Arming countdown before anything dials — §7. Three ways to stop it:
      say cancel, touch anywhere on the screen, or press the button
- [x] Cancel keywords wired to the countdown. Saying **help** during it does
      *not* cancel — that would be the opposite of what was asked for
- [x] Receipt naming every leg's outcome, spoken and shown from one wording,
      so what is heard and what is read cannot drift
- [x] Failed legs named as failed. "No contact saved" reads differently from
      "the call did not connect" — different remedies, different sentences

**Voice** — the parser and its tests already exist; these are the handlers

- [x] `whereAmI` handler — §2.C, reporting the *quality* of the answer, not
      just an answer
- [x] `callGuardian` handler — §2.C. Never quietly rings the emergency
      contact instead; a user who asked for their guardian would not know
- [x] `connectDevice` handler — §2.C, honest about §5 being out of scope
      rather than pretending to search for hardware that does not exist
- [x] "What can I say?" — generated from `kVoiceKeywords`, so it cannot drift
      from what the parser accepts. Lists the Filipino variants too

**Other**

- [x] Repeat on Scan — as a button, as a tap anywhere on the camera view, and
      as the spoken command "repeat". Three routes, because a user mid-walk
      may have only one of them free
- [x] Consent centre — inspect and revoke, in the same words onboarding used.
      Revocation is enforced by the rules, not by hiding a button
- [x] What the app has learned — list and delete, backed by Phase 2. Wording
      stays modest: it has counted something, not learned something
- [x] Device connect reachable from settings — §5. So are the emergency
      contact, the guardian invite and the safety notice
- [x] **Offline-tolerant first run** — consent, contact and guardian count
      cached locally, so a returning user with no signal reaches a working
      dashboard. A corrupt cache reads as empty, understating what is set up
      rather than overstating it

**Gate:** all of onboarding completed with VoiceOver on and **Screen Curtain
enabled**. Screen fully black, start to finish.

---

## Phase 5 — Accessibility, docs, defense `S`

- [x] Every control on **every** screen carries a semantic label —
      `test/app/accessibility_gate_test.dart` walks all 17 and fails on any
      unlabelled tappable element
- [x] No overflow at 2.0× text scale, every screen. Found two real bugs: the
      dashboard cut off the SOS button, and Settings cut off "Back"
- [x] Flow test: setup resumes at the first incomplete step, checked at every
      point in the flow rather than one
- [x] `flutter build apk && flutter build ios && flutter build web` — all
      three green. Getting there took seven fixes no test would have caught
- [x] Skip every skippable step; SOS still works
- [x] SOS with no contact and no guardian says nobody was reached, and names
      the alarm as the one thing that did happen
- [x] Revoking location consent is denied **server-side** — see the rules
      suite, "a paired guardian is refused while location consent is off"
- [x] Offline: the dashboard reads from local storage, so a set-up user with
      no signal reaches a working SOS. The physical airplane-mode pass is
      step 6 of the demo script
- [x] Demo script with a network-failure path — [`DEMO.md`](DEMO.md)
- [x] Scope table — [`SCOPE.md`](SCOPE.md), ready to paste onto a slide

**Gate:** someone who has never used the app completes onboarding blind.

---

## Port from `cprwire` — do not rewrite these

The old repo at `~/kokey/CapstoneImpairgency/cprwire/` is reference-only.

- [x] Camera + detection loop ported. **ML Kit was never used** — cprwire
      declared `google_mlkit_object_detection` and ran an SSD MobileNet
      through TFLite instead. Leaving ML Kit out keeps iOS simulator builds
      working. The guidance policy is now pure and tested in
      `core/vision/`; only the camera and interpreter plumbing is in `data/`.
      The SSD itself has since been replaced by YOLO11n, which ends at the
      head rather than at a post-process node — so the thresholding and the
      suppression an SSD graph does for you are now in `core/vision/yolo.dart`
      and tested there. See `docs/VISION.md`
- [x] Contact picker — **the system picker, over a method channel of our
      own**, and the reason no package is used is worth keeping.
      `flutter_contacts` force-unwraps
      `UIApplication.shared.delegate!.window!!`, nil since iOS 13, and crashes
      on launch. `flutter_native_contact_picker` wraps the system picker
      correctly but declares Java 1.8 against Kotlin 17 and breaks the Android
      build outright. So `MainActivity.kt` fires `ACTION_PICK` and
      `AppDelegate.swift` presents `CNContactPickerViewController`: one row
      comes back, never the address book, and no contacts permission is
      needed for it. The screen still takes an injected picker, so tests run
      without a phone
- [x] ~~OTP Cloud Functions~~ — **obsolete.** Replaced by Firebase Auth's own
      `sendEmailVerification()`: free, no server, and it stores nothing. A
      database of live login codes is an account takeover waiting to be found
- [x] Voice command vocabulary + tests — *ported and extended to six commands*

---

## Tester feedback round — one tester, one device, thirteen items

What came back from the first person outside the team to use the build,
grouped the way they grouped it. Three of the P0s were not device problems:
they were features that had never been wired, and the tester was the first
to notice because nobody on the team had been the person the app is for.

**P0 — broken**

- [x] Voice commands did not work *at all* — because nothing listened.
      `speech_to_text` was declared and imported nowhere. Now: permission →
      `SttSpeechRecognizer` → `VoiceController` → parser → `VoiceActions` →
      router, and every break in that chain is said out loud and written
      under the microphone button. The dashboard listens after it asks; the
      SOS countdown listens for "cancel" without silencing its own count
- [x] "Stop, tree in front of you" came out as "Stop. Stop. Stop." — every
      camera frame restarted the sentence. One `SpeechQueue` for the whole
      app: hazard > navigation > information, a hazard interrupts anything
      but an identical hazard already being said, nothing else cuts a
      sentence short. `test/core/speech/` asserts the rule
- [x] The emergency contact did nothing — three things at once. The saved
      contact never reached the device cache SOS reads from until the next
      launch; `guardianCount` was read from a field nothing wrote, so the
      guardian event was never written; and offline, the Firestore write
      held "Calling for help…" forever. All three fixed and tested, and the
      receipt gained `LegOutcome.pending` for an alert queued for a
      connection — neither reached nor failed, and said as neither

**P1 — missing screens**

- [x] Who is this account for? — visually impaired user or guardian, before
      Create account. The role is cached on the device before the account
      exists, so the guard never sends a guardian through the wrong flow
- [x] About you — name, age, type of impairment as a list of six with
      Other, an optional phone number for the guardian's Call button.
      Step 2 of 7; writes `displayName` for the dashboard and the Function
- [x] Forgot your password? — Firebase's own reset link, worded so the form
      cannot be used to learn which emails are registered
- [x] Guardian registration — name, email, password, phone, and the code;
      the code's shape checked before anything is sent, its validity
      answered in the pairing code's own words under the field
- [x] Guardian dashboard — who they watch, a location line that is true
      when read alone, a recent SOS first, Call and Open on a map. Also
      where `SosWatcher` is finally started; it had never been constructed

**P2 — feature changes**

- [x] Several emergency contacts, in calling order. The list is the order;
      the legs ring the first, the receipt offers the next by name and a
      text to all; every number goes on the SOS event. Import from the
      phone through the system picker. Order documented in
      [`EMERGENCY_DELIVERY.md`](EMERGENCY_DELIVERY.md)
- [x] Directions in Scan — say where you are going, be told which way and
      how far. **Straight-line, not routed**, and introduced as such: there
      is no road network on the free tier. Navigation priority, behind
      hazards. `core/navigation/guidance.dart`
- [x] Saved places — Home, Work, School and the rest as one-tap buttons in
      Smart assistance; saved by standing in them; added, renamed and
      removed under Settings. Owner-only in the rules, with a test that a
      guardian is refused even with location consent
- [x] Read text — its own button, its own screen, one photograph, the words
      in pieces with pause, say that again and next. ML Kit's text half is
      the one new dependency, with its reason in `pubspec.yaml`
- [x] Settings — two entries added and nothing else touched: *Emergency
      contacts* (was singular, now says how many) and *Saved places*

**Assumptions made, to be checked with the tester**

- The guardian's Call button rings the *user's own number* when they gave
  one and their emergency contact otherwise, and says which. "Same target
  as the user-side SOS" would otherwise mean a guardian ringing themselves
- Directions are straight-line. If turn-by-turn on roads is what was meant,
  that needs a routing service and a billing account, and belongs on the
  scope table with a reason. *(Round 2: it was meant. Built on OpenStreetMap's
  free router, with the straight line as the fallback.)*
- The phone number on About you is not in the tester's list. It is there
  because the guardian's Call button needs a target; it is optional and
  says why it is asked

---

## Tester feedback round 2 — September 15

The testers' second list, in Filipino, covering the dashboard, the user app and
the guardian app. Two items reversed decisions in [`SCOPE.md`](SCOPE.md):
recognising friends, and turn-by-turn directions. Both are built on the terms
the scope table now states.

**Guardian**

- [x] Create account then lands on the guardian dashboard. Registration and
      the code both succeeded; nothing navigated, and a second press said
      the email was taken. A second press now carries on with the account
      already made, and each error sits under its own field
- [x] Guardian registration that fails partway says which part, and keeps
      what was done: the account is made, only the code is left

**Sign-in**

- [x] New accounts confirm their email before reaching the app — §7. A
      made-up address got straight in. Accounts made before the cutoff are
      not held. Addresses are checked for shape everywhere one is typed
- [x] Rules: claiming an invitation needs a confirmed email

**Admin**

- [x] Filters: all, visually impaired, blind, low vision, colour blind,
      other, guardians, admins — with counts, and a search — §1.2
- [x] Add an account without choosing its password: the person gets an
      email to set their own
- [x] Edit name, age, impairment, phone and role; a role change removes the
      account's links, and says it will
- [x] Remove an account: tombstone first, then links, codes and history; the
      phone signs itself out and says why once. Rules lock the account out
- [x] Browser tests for all of it — `test/e2e/users.spec.js`

**Read Text**

- [x] The buttons broke their labels a letter or two per line. They stack on
      a phone and keep a row on a tablet, measured at the current text size
- [x] Say "read" or "basahin" instead of pressing Read; pause, continue,
      next and again by voice; a page read aloud is not heard as commands

**Voice**

- [x] "Tap to speak" did nothing: scan and navigate opened the screen the
      user was already on, and a tap during automatic listening closed the
      microphone without a word
- [x] Hands-free: the microphone reopens by itself on the main, scan, read
      and where-to screens; a switch in Settings; backs off and says so when
      the microphone keeps failing — §2.C
- [x] The app's own speech is not heard as a command; hazard warnings close
      the microphone until they have been said
- [x] More commands: take me to a place, stop directions, go back (asked
      first on Scan), who is here, hello friend, forget, what can I say
- [x] "Where am I" stopped reading the SOS receipt's "your location was
      sent"; "call my guardian" stopped claiming to call
- [x] Buttons Voice Access and Switch Access can press: every button's
      semantics carries its tap

**Directions**

- [x] Walking routes from OpenStreetMap (routing.openstreetmap.de), turn by
      turn: ahead of each turn and at it, a second turn close behind riding
      along, the wrong way said, off the route rerouted within limits
- [x] Every failure named, and the straight line as the fallback, said to be
      one
- [x] "Take me to Jollibee": places searched near the user (Photon), each
      offered in turn, yes, next or no. Typed search in Smart assistance and
      Saved places
- [x] "Where am I" names the street when the map can say quickly
- [x] OpenStreetMap credited on the scan screen and on the guardian's map
- [x] Real OSRM and Photon answers recorded between two Malolos landmarks
      (`test/core/navigation/recorded/`). A walk along the real route is
      guided turn by turn in a test; the real search found two Jollibees on
      one highway being merged, now fixed
- [ ] Walk a route on a real phone in Malolos: prompt timing at walking
      pace, off-route false alarms at 10–20 m GPS error

**Friends**

- [x] "Hello friend Sam": Sam is asked out loud, and only a yes saves
      anything. Five clear views of one face; refusals said with their
      reason — §2.A.6
- [x] "Your friend Sam is approaching", seen twice before it is said, once a
      minute per friend, never over a hazard — §2.B.3
- [x] Faces kept on the phone as numbers, excluded from Android and iOS
      backups, deleted when the consent is turned off and at sign-out
- [x] People I know, under Settings: forget one, or everyone
- [x] BlazeFace downloaded from Google's MediaPipe assets; hash and tensor
      shapes checked (`tool/tflite_shapes.py`)
- [x] MobileFaceNet: agree the exact file and its weights' licence, then add
      it — see [`VISION.md`](VISION.md) (added in round 3)
- [ ] Calibrate the match threshold with volunteers, at 0.5–3 m, in daylight
      and indoors

**Found on the way**

- [x] Leaving a screen stopped the next screen's speech and the SOS
      countdown's listening, and dropped queued hazard warnings
- [x] The SOS countdown could hear itself say "cancel"
- [x] Saved places did not refresh after a save
- [x] Consent screen said four switches; there are five
- [x] Android backups: rules added, leaving out saved faces
- [x] Crash reporting switched on — §1.4. `firebase_crashlytics` was a
      dependency that nothing initialised, so errors in the app's own code
      went unreported while System health said otherwise (from #77)
- [x] A phone with no speech engine stays open and silent, and reports it
      once, instead of throwing from the first screen (from #77)

---

## Tester feedback round 3 — September 16

The testers' third list. Two of its seven items - friends, and "take me to any
place" - were built in round 2 and reached them after the list was written.
The rest is below. Decided with Dex on 2026-09-16: a depth model behind a flag
for walls; voice on every screen, every button by its label and every text
field by dictation, passwords never; the SOS countdown stays three seconds.

**Voice** — §2.C

- [x] Every screen listens. Hands-free worked on four screens, because only
      four attached a voice scope; the rest had nothing to listen for. Not on
      the first run's safety notice (the microphone prompt waits for it), not
      during SOS, and not in the guardian's app
- [x] A microphone button on every screen of the user app
- [x] Any button is pressed by saying what it says - icons and choice rows
      too, by the label a screen reader reads. A command said on its own is
      still the command, and help is always help. Two buttons that both match
      are asked about. A press is named as it happens, and that name heard
      back is not a second press
- [x] Forms by voice: say "fill in", or "say the email address". What was
      heard is read back - an email letter by letter, a phone number in
      threes - and kept only on a yes; anything else is taken as the answer
      said again. Emails, names, ages, phone numbers, place names and the
      search box. Passwords never — §7
- [ ] On a phone: Filipino names and a Gmail address through the platform
      recogniser; the first run's microphone prompt

Out of scope: voice on the guardian's screens. They are used by someone who
can see them.

**Admin** — §1.1–§1.3, §6

- [x] The sidebar "did not work": a roster read that failed for want of an
      answer - offline, a cold start - was kept as "not an administrator" for
      the rest of the session, so every click went to the sign-in page. A
      refusal and no answer are now told apart; no answer is asked again, and
      the sign-in page says the roster is still being checked
- [x] A page that cannot reach the database says so instead of blaming the
      roster, and one that hangs gives up after 15 seconds, in words
- [x] Clicking the section already open reloads it, visibly. It used to do
      nothing at all
- [x] Sidebar entries are buttons to a screen reader, the open one selected
- [x] Browser test: an administrator opens every section through the real
      router, the real roster read and the real rules

**Scan** — §2.A.1, §2.A.3

- [x] "Path looks clear" is "No known objects in view", said when it becomes
      true and every 20 seconds after, not every 3. The model has no walls,
      doors, posts, kerbs or steps — §7
- [x] What to name first weighs what it is: a car before a chair of the same
      size, and a thing held in a hand never "Stop"
- [x] Said sooner: "close" from a quarter of the frame, and 600 ms between
      two different sentences
- [x] Walls, doors and posts from a depth model, MiDaS v2.1 small (MIT),
      behind `--dart-define=DEPTH_WARNINGS=true`; off by itself on a phone too
      slow for it. See [`VISION.md`](VISION.md), "Depth"
- [x] Add the depth model for a device-check build: 66 MB, MIT, not committed.
      On the test release as `impairgency-8c4014a-depth-check`
- [ ] Depth device check: walls, a glass door, posts, a table edge, a parked
      motorcycle, open and narrow corridors, a slope down

**Smart assistance** — §2.C, §2.A.7

- [x] A map. Directions have their own screen: the route, where the user is
      and where they are going, the next instruction in large type, and the
      camera in a corner. Scan is the surroundings; Smart assistance is
      getting somewhere; both warn about obstacles and people
- [x] "Stop directions" goes to Scan, which keeps warning. Scan used to stay
      put and forget the destination by hand, and got it wrong
- [x] "Somewhere else" first on the chooser: a place by name, said or typed
- [ ] On a phone: the camera handed from Scan to the map and back; a real walk
      in Malolos following the map

**Friends** — §2.A.6, §2.B.3

- [x] Built in round 2; the file for the recogniser is agreed (see
      [`VISION.md`](VISION.md), "Faces")
- [x] Download MobileFaceNet (5.2 MB; weights for research use), check its
      shapes, record its hash: `[1,112,112,3]` to `[1,192]`, hash in
      [`VISION.md`](VISION.md)

**SOS** — §2.A.5

- [x] Saying "cancel" did not stop the countdown. Its one listening window
      heard the countdown talking, took that out as the app's own voice, and
      closed with seconds to go. The microphone now reopens for as long as
      the countdown runs
- [x] "Cancel" is acted on as soon as the recogniser hears it, not after two
      seconds of silence - unless the app itself may be the one saying it
- [x] "Cancel" still works after the countdown, while the alarm sounds and
      the position is found, until the dialler opens: nobody is called, no
      guardian alerted, and it is recorded as cancelled before the call
- [x] The countdown's "Say cancel, or touch the screen" was cut off by
      "Calling Mum in 2" a second in, so nobody heard how to stop it. The
      count waits for it; the screen still counts every second
- [ ] On a phone: a "cancel" heard over the countdown's own voice, on Android
      and on iOS

Voice cannot reach the phone's own call screen: once the dialler opens, the app
is behind it. The docs say so.

**Found on the way**

- [x] A camera still held by the screen before is asked for again, and one
      that will not open says so instead of "Starting…" for ever
- [x] Dead `Routes.adminSessions` removed
- [x] The consent switches, the settings icon, and the rename, remove and
      move-up icons are pressable by name too

## Tester feedback round 4 — September 18

The fourth list, from the Sept 16 build (`impairgency-8c4014a-release`) and
the dashboard deployed from it. Worked in the order asked: SOS and admin,
then voice, navigation, scan. Decided with Dex on 2026-09-23: train a stairs
class now; hands-free stays opt-in on iOS this round; command matching stays
on the phone (near misses and synonyms, no language-model service); session
summaries are written this round.

**SOS** — §2.A.5

- [x] "Cancel" and "stop" acted late: the hint "Say cancel, or touch the
      screen anywhere, to stop this" had both words mid-sentence, so a
      partial "cancel" waited for the phrase to end - past the three
      seconds. The hint is now "Say cancel." and "Or touch the screen
      anywhere.", and both words act on the first partial
- [x] The record is written before the dialler opens, under an id chosen
      then, with status active - a phone dropped mid-call lost it
- [x] After the call: the receipt says "If you are all right now, say: I am
      okay", listens for it (and "cancel", "ayos lang", "false alarm"; help
      calls again) when it appears and again on coming back from the dialler,
      and has an I'm okay button. The record is resolved by the user - not
      cancelled - and the guardian's phone replaces "needs help" with "says
      they are okay"; the card turns green
- [x] False alarms: with hands-free on, help is a phrase of three words at
      most with no negation; a button named exactly beats help in its name
      ("Emergency contacts"); bare "guardian" is a Settings button, not a
      call; with a screen reader on, the labels it reads are not the user
- [x] What the app tells the user to say is no longer deleted as its own
      echo - "I am okay", "fill in", "create account"
- [ ] On a phone: say "stop" and "cancel" over the countdown; fire an SOS,
      hang up, say "I am okay"; the guardian's phone and the dashboard row
- [ ] ~~Cancel with the volume buttons~~ — Android only, and untestable in
      widget tests. Revisit if testers ask
- [ ] ~~Hear "stop" during the call, or end it from the app~~ — the phone
      call owns the microphone on both platforms, and iOS lets no app end a
      call. See [`SCOPE.md`](SCOPE.md)

**Admin** — §1.1–§1.4

- [x] Emergencies reach the dashboard: System health lists every SOS of the
      last 30 days - when, who, where with a map link, who was called, and
      active, cancelled or resolved - and an administrator can mark one
      resolved. The tiles count the records themselves
- [x] Rules: an administrator may change `resolvedAt`, `resolvedBy` and
      `status` on an SOS record and nothing else; nobody moves one onto
      another user. Six rules tests
- [x] Overview says why journeys are blank - recorded only with history on -
      instead of blanking the emergencies with them; active users counts
      anyone who shared a position
- [x] The Firebase console links open in a new tab
- [x] Journeys are recorded, and summarised for the dashboard: a session is
      a journey from choosing a destination to arriving, stopping, signing
      out or ten minutes away; fixes, directions, obstacles, stairs and SOS
      stages share its id. Only with history consent; only a saved place's
      own name goes in a summary
- [x] Browser tests: SOS rows, Mark resolved through the real rules, and
      both kinds of empty Overview
- [ ] Deploy the rules, indexes and hosting (after Dex confirms), and check
      `firebase firestore:indexes` lists both `sos_events` indexes
- [ ] On the emulator: a journey with history on writes a summary; with it
      off, nothing

**Voice** — §2.C

- [x] Near misses: one edit off a keyword of five letters or more counts -
      not for cancel words, where/there/here, or a short keyword
- [x] Tagalog particles ("dalhin mo ako sa") and more fillers are passed
      over; "where is", "saan ang", "find", "hanapin" ask the way; "where"
      alone is nothing
- [x] Everyday words now include stop (the app stops talking), back,
      friends, who is here, and hands-free on and off - stop, back, who is
      here and hands-free only as the whole phrase
- [x] Hands-free: a failing microphone is tried again on the next screen; a
      refused one is explained again on coming back; the first window says
      "Hands-free listening is on. Just speak."; 100 ms between windows; a
      near miss gets "I heard …, you can say …" at most every 20 seconds
- [x] Dictation: six seconds to start, 2.5 s pauses, 20 s windows, the
      platform's dictation mode, a buzz when the microphone opens. Replies
      are edits first - done, cancel, no, clear, delete last word, read back,
      spell it, add … - and an email that is not complete is not kept
- [x] Addresses as people say them: "my email is", "at the rate",
      "under score", "dotcom", "twenty two", "jay dee ee ex", accents folded
- [ ] iOS: try `onDevice: true`, then default hands-free on after the first
      permission grant
- [ ] A listening tone as well as the buzz: needs an audio asset
- [ ] On a phone: the voice-only checklists in [`DEMO.md`](DEMO.md)

**Smart assistance** — §2.C, §2.A.7

- [x] Search results are the screen's buttons, first and numbered, and all
      of them are read out; "number two", "the second", "ikalawa" choose one;
      two branches with one name ask for the number
- [x] Search without a position: it runs anyway and says so, or says how old
      the position is; ten results, in English; map-service failures are
      reported to Crashlytics
- [x] Turns are no longer dropped by the next thing said; "Keep going. Turn
      left in about 120 metres." between turns; a vague position said once;
      standing still is not "lost"; a course nobody reported is not due
      north, and one is worked out from the walk; a position stream that
      stops is said
- [ ] On a phone, outside: a walked route - turns, progress, arrival - and
      standing still for 40 seconds

**Scan** — §2.A.3, §2.A.6

- [x] The banding heuristic is retired. Stairs come from a second,
      single-class YOLO11n run every 500 ms beside the COCO model, as
      detections: weighted with the cars, named with where, told to the
      guardian, kept on the journey. "Stop" for stairs waits for the gate
- [x] Tools: `fetch_stairs.py` (Open Images "Stairs", floors as negatives),
      `train_stairs.sh`, `eval_detector.py --stairs`
- [ ] Fetch the data and train the model (asks first: Open Images, and
      Ultralytics' `yolo11n.pt`), check its shapes, record its hash
- [ ] Measure it: close recall and floors firing per score, into
      [`VISION.md`](VISION.md). "Stop" on only if close recall ≥ 70% and ≤ 5%
      of negatives fire at 0.55
- [x] "Hello friend Sam" from the home screen; with recognition off it asks
      to turn it on; the real reason when it cannot run
- [x] Ten seconds to take a face down, counted aloud
- [x] "Who do I know", "rename Sam to Samuel" (and a Rename button),
      "forget everyone" after a yes
- [x] Each bundled model is named in `pubspec.yaml`, so MiDaS never ships to
      testers; `tool/build_depth_check.sh` adds it for that one build
- [ ] On a phone: meet a friend from the home screen; a staircase, a tiled
      floor, a zebra crossing and a striped rug once the model is in

---

## Out of scope — do not build

Declared in the documentation with reasons. If one of these gets built anyway,
the reason it was scoped out was wrong — argue that first, in writing.

- [ ] ~~Recognising anyone who has not agreed~~ — §2.A.6, §2.B.3 — friend
      recognition is built for people who said yes when saved; contacts,
      photos and strangers stay out
- [ ] ~~Bluetooth / IoT hardware~~ — §5 — no device exists to pair with
- [ ] ~~Fire and emergency exit guidance~~ — §2.A.2 — needs indoor floor plans
- [ ] ~~Video session recording~~ — §1.1 — substituted by the Phase 2 timeline

Partial: **stairs detection** (§2.A.3). It is a fall risk. The floor-banding
heuristic is retired; stairs now come from a trained single-class detector
whose pipeline is built and tested, and whose model is being trained. Until
the file is in a build the app says nothing about stairs, and until it has
been measured it names them and never says "Stop" — see
[`VISION.md`](VISION.md), "Stairs".
