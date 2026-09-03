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
| 4 | **Guardian alert** | A pairing, the guardian app running, notification permission, data | Receipt names how many guardians were reached out of how many exist. |
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

### Guardian alerts

**How it works now.** The guardian app holds a Firestore listener on
`sos_events` for the users it is paired with, and raises a local notification
when one appears. No server involved, and nothing to pay for.

**The honest trade-off.** A server pushes to a phone that is asleep; this only
works while the guardian app is running. On Android a foreground service keeps
it alive indefinitely. On iOS the system suspends background execution after a
few minutes, so a guardian whose phone has been in a pocket since this morning
will not be interrupted.

This is a deliberate choice, not an oversight. Server-side fan-out needs Cloud
Functions, Cloud Functions need a billing account, and this project has decided
not to have one. The production path is **written and waiting** in
`functions/index.js`; the day the project can deploy it, the guardian sees the
same notification from the same channel and nothing else changes.

What is deliberately *not* done: sending FCM directly from the app with a server
key baked in. That key is extractable from any APK, and whoever extracts it can
notify every user of the app. Several tutorials suggest it. It is a credential
leak with extra steps.

**Two independent guards against noise.** A Firestore listener replays its whole
result set when it attaches, so without a bound every launch would fire every
past emergency at once — and the one that mattered would be buried in them. The
query is bounded by `kAlertableAge`, and `shouldAlert` checks it again; the
second check is the one that decides. Cancelled events never alert, and an
event already shown never shows twice.

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

## What is deliberately not built

Both of these were reachable by spending money. The project chose not to, and
each has a free path that works.

| Not built | Cost avoided | What is done instead |
|---|---|---|
| Server-side push fan-out | Blaze plan, needs a card on file | Guardian-side Firestore listener raising a local notification. Reliable on Android; time-limited on iOS. |
| iOS remote push | Apple Developer Program, $99/year | Android is the demo platform. iOS still does alarm, phone call, location and scan; only remote push to a guardian's iPhone is unavailable. |

Neither is a gap in the work. Both are recorded on the scope table with the
reason, the same as face recognition and Bluetooth.

## The manual test that matters

Fire an SOS with no emergency contact, no guardian, and airplane mode on. The
alarm must sound, and the receipt must say — out loud — that nobody was
reached. If it says anything more optimistic than that, it is a defect.
