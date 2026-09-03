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
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `████████████` | 21 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `████████████` | 10 / 10 |
| Port from `cprwire` — do not rewrite these | `██████░░░░░░` | 2 / 4 |
| **Overall** | | **80 / 85  (94%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `████████████` | 21 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `████████████` | 10 / 10 |
| Port from `cprwire` — do not rewrite these | `██████░░░░░░` | 2 / 4 |
| **Overall** | | **80 / 85  (94%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `████████████` | 21 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `████████░░░░` | 7 / 10 |
| Port from `cprwire` — do not rewrite these | `██████░░░░░░` | 2 / 4 |
| **Overall** | | **77 / 85  (91%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `████████████` | 21 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `████░░░░░░░░` | 3 / 10 |
| Port from `cprwire` — do not rewrite these | `██████░░░░░░` | 2 / 4 |
| **Overall** | | **73 / 85  (86%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `████████████` | 21 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `██████░░░░░░` | 2 / 4 |
| **Overall** | | **70 / 85  (82%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `███████████░` | 20 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **68 / 85  (80%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `███████░░░░░` | 13 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **61 / 85  (72%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `██████░░░░░░` | 10 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **58 / 85  (68%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `█████░░░░░░░` | 8 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **56 / 85  (66%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████████` | 12 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **48 / 85  (56%)** |
|---|---|---|
| Phase 0 — Security and integrity `S` | `███████████░` | 18 / 19 |
| Phase 1 — Location, push, pairing `M` | `██████████░░` | 10 / 12 |
| Phase 2 — Location history and aggregations `M` | `████████████` | 7 / 7 |
| Phase 3 — Web dashboard `M` | `████████░░░░` | 8 / 12 |
| Phase 4 — Flow, SOS, voice `L` | `░░░░░░░░░░░░` | 0 / 21 |
| Phase 5 — Accessibility, docs, defense `S` | `░░░░░░░░░░░░` | 0 / 10 |
| Port from `cprwire` — do not rewrite these | `███░░░░░░░░░` | 1 / 4 |
| **Overall** | | **44 / 85  (52%)** |
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
- [ ] `firebase deploy --only storage` — **the one thing still blocked.**
      Provisioning a bucket needs a location chosen in the console; there is no
      CLI path. Nothing in scope stores a file, so this waits until something
      does. `storage.rules` is written, committed and correct
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
      `core/vision/`; only the camera and interpreter plumbing is in `data/`
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
