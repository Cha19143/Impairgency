# How an SOS reaches someone — and every way it does not

Requirements §7 asks that emergency features "be thoroughly tested and have
fallback options when possible". This is the fallback register: each leg of an
SOS, what can stop it, and what the app says when it does.

The governing rule is the one from §7's other clause — **the app never implies
success it did not have.** A receipt that says "help is on the way" when nothing
was delivered is worse than no receipt, because the user stops trying.

## The legs, in order of independence

Ordered so the ones that need least go first. A phone with no signal, no
account and no guardian can still do the first.

| # | Leg | Needs | If it fails |
|---|---|---|---|
| 1 | **Alarm** | Nothing but the speaker | Only a hardware fault. Always attempted first and never gated on anything else. |
| 2 | **Phone call to the emergency contact** | A saved contact, a dialler, cell signal | Receipt says the contact was not reached. Works with no data connection, which is why it outranks push. |
| 3 | **Location attached to the event** | Permission, device location on, a fix | Sent anyway if stale, always labelled with its age. Four distinct failures, four distinct sentences — see `lib/core/location/location_policy.dart`. |
| 4 | **Guardian push** | A pairing, a live token, notification permission, data | Receipt names how many guardians were reached out of how many exist. |
| 5 | **Guardian sees location** | All of 3 and 4, plus location consent | Consent is separate from pairing on purpose. Being someone's guardian and being allowed to track them are two decisions. |

Legs 1 and 2 are on-device. **Legs 3–5 are the ones that can silently do
nothing**, and they are the reason the receipt exists.

## Where each leg actually breaks

### Location

Four causes, four remedies, four sentences. "Location unavailable" is never
said, because it is true for all four and useful for none.

- **Never asked / declined once** — recoverable, the app asks again next time
  and says what SOS cannot do meanwhile.
- **Declined permanently** — only Settings can fix it, so that is what the app
  says. It stops asking.
- **Device location off system-wide** — a different Settings screen, named.
- **Timed out** — common indoors. Falls back to the last known fix, sent with
  its age attached.

A fix older than two minutes is never called "your location". It is sent —
an old position still narrows a search — and always described as last known,
with how long ago. A guardian seeing a pin from this morning while the user is
across town has to know which it is.

### Guardian push

Delivery is fanned out by a Cloud Function on the SOS document, not by the app.
The phone may be dropped, dead or out of signal a second after the write. Once
the document lands, delivery stops depending on the phone staying alive.

**Android.** High message priority wakes a dozing device; the
`impairgency_emergency` channel at `IMPORTANCE_HIGH` carries the sound and the
heads-up. Both are needed — priority alone lands silently on a default channel.
On Android 13+, `POST_NOTIFICATIONS` is a runtime grant, and a guardian who
refused it will not be told anything.

**iOS.** This is where the honest limit is. Apple's *critical alerts* — audible
through silent mode and Do Not Disturb — need an entitlement granted case by
case, and this project does not have one. The app requests it, degrades to
`time-sensitive` when it is refused, and **tells the guardian in plain words**
that alerts will not come through Do Not Disturb unless they add ImpairGency to
their allowed apps. Saying so *is* the fallback. See
`lib/core/alerts/reachability.dart`; the wording is asserted in tests, including
that no state promises an alert will always arrive.

**Stale tokens.** Tokens rotate on reinstall and restore. FCM rejections are
pruned after every send, because a dead token makes the success count a lie.

### Nobody to reach

Skipping the emergency contact and skipping the guardian invite are both
allowed. Neither is silent: onboarding says what SOS can and cannot do without
them, and the receipt after an SOS says nobody was reached rather than nothing
at all.

## What is not built yet

- **Cloud Functions need the Blaze plan.** Firestore rules and the client work
  on Spark; function deployment does not. Until the project is upgraded, an SOS
  writes its document and no guardian push goes out. The free tier covers a
  capstone's volume many times over, but it needs a payment method on file.
- **APNs key.** Needs an Apple Developer account; iOS push does nothing without
  it.
- Both are tracked as issues rather than left as surprises.

## The manual test that matters

Fire an SOS with no emergency contact, no guardian, and airplane mode on. The
alarm must sound, and the receipt must say — out loud — that nobody was
reached. If it says anything more optimistic than that, it is a defect.
