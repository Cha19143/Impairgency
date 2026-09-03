# Demo script

Twelve minutes, six steps, and a network-failure path that is part of the demo
rather than a thing to be avoided.

**Before you start**

- Two phones: one Android (the visually impaired user), one anything (the
  guardian). Android is the user's phone because iOS remote push needs a $99
  Apple membership this project chose not to buy.
- The web dashboard open at <https://impairgency-capstone.web.app>, signed in.
- Airplane mode ready to toggle on the user's phone. Do not hide it.
- The app freshly installed, so the demo starts where a real user starts.

---

## 1 — The first thing the app says (1 min)

Launch it. Do not touch anything; let it speak.

> *"What this app can and cannot do. ImpairGency helps you notice what is
> around you. It will not always be right. It can miss a step, a low branch, or
> a car that is moving. Keep using your cane, your dog, and your own
> judgement."*

**Say:** requirements §7 asks that AI guidance "should not guarantee that an
environment is completely safe". Nothing in the 17 submitted screens said so.
This is the first thing the app says, before it asks for anything.

## 2 — Onboarding, blind (3 min)

Turn **VoiceOver or TalkBack on**, and if you can, **Screen Curtain** so the
display is black. Complete onboarding without looking.

Points to make as you go:

- **Create account is step 1 of 6.** In the submitted design it was step 5 of 5,
  behind a login screen for an account that did not exist yet.
- **The keyboard types the password, not the microphone.** The design offered to
  "speak the details instead of typing".
- **Skip the emergency contact.** It answers out loud: *"an emergency SOS can
  sound the alarm and share where you are, but it will have nobody to call."*
  Then the button becomes "Skip anyway". Skipping is allowed; skipping silently
  is not.
- **Consent is four switches, all off.** Read one aloud — each says who can see
  the result.

## 3 — Guardian pairing (1 min)

On the user's phone, invite a guardian. The code is read out one character at a
time: *"F, H, 2, 9. Then: M, R, 4, 7."*

**Say:** the alphabet has no B, D, E, G, P, T, V or Z, because they all rhyme,
and no I, L, O, S, 0, 1 or 5, because they are confusable. It is eight
characters rather than six because any signed-in account can look a code up, so
the code space is the only thing between a stranger and enumeration.

Enter it on the guardian phone. They are now paired.

## 4 — SOS, and the countdown that means something (2 min)

Press **EMERGENCY SOS**. It counts down out loud: *"Calling Mum in 3… 2…"*

**Cancel it by tapping anywhere on the screen.** Not the button — anywhere.

> *"Cancelled. Nothing was sent and nobody was called."*

**Say:** in the submitted design, Cancel appeared *after* dialling started.
Cancelling a call already placed is not cancelling. Nothing dials until the
countdown ends, and the whole screen is the cancel target because someone who
has put the phone in their pocket cannot find a button.

Now fire it for real. The guardian's phone alerts. The receipt reads out every
leg: alarm, call, location, guardian.

## 5 — The receipt tells the truth (1 min)

Remove the emergency contact in Settings, then fire SOS again.

> *"Nobody was reached. The alarm is sounding. No emergency contact is saved, so
> nobody was called."*

**Say:** this is the part that matters. A receipt that says "help is on the way"
when nothing was delivered is worse than no receipt, because the user stops
trying. There is a test asserting the app never says it.

## 6 — Airplane mode (2 min)

**Turn airplane mode on. Then open the app.**

It reaches the dashboard. The alarm sounds, the dialler opens, and the receipt
says the location and guardian legs failed — naming which, not "something went
wrong".

**Say:** account-first onboarding means an unregistered phone with no signal is
a phone with no SOS. That is a real cost, so consent, contact and guardian count
are cached locally and a returning user never depends on the network to get to
the alarm. This is §7's "fallback options when possible", demonstrated rather
than claimed.

## 7 — The dashboard, and what it refuses to say (2 min)

Open the web dashboard.

- **Overview** — the five metrics §1.3 names, from real sessions.
- Point at **Detections**: *"Counts of what the app reported, not accuracy.
  Measuring accuracy would need someone to label what was actually in each
  scene."* The screen this replaces hardcoded `99.2%`.
- **Accessibility results** — the measured contrast of every colour pair the app
  renders, computed live from the same constant the app paints with. All eight
  clear AA. The old app's largest buttons were white on cyan, about 1.1:1.

Close on the scope table in [`SCOPE.md`](SCOPE.md).

---

## If something fails live

- **The guardian phone does not alert.** Say so, and explain why: server-side
  push needs Cloud Functions, which need a paid plan. The guardian app holds a
  Firestore listener instead, which works while the app is open. Open it and
  fire again. `functions/index.js` is the production path, written and waiting.
- **Scanning finds nothing.** The model is an SSD MobileNet; point the camera at
  a chair. If it still finds nothing, use the Repeat button to show the guidance
  path works and move on — do not debug live.
- **The web dashboard is empty.** It says "No sessions yet" because nothing has
  been recorded with history consent on. That is the correct empty state, and
  worth saying: the screen it replaces would have shown zeroes that read as
  measurements.
