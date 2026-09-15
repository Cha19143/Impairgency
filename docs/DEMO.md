# Demo script

Eighteen minutes: seven steps, the testers' second round, and a network-failure
path that is part of the demo rather than a thing to be avoided.

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
- **Consent is five switches, all off.** Read one aloud — each says who can see
  the result.
- **Try a made-up email first.** Create an account with one: the app stops at
  *Check your email* and does not let it in. Then use a real address and press
  the link in the email.

## 3 — Guardian pairing (1 min)

On the user's phone, invite a guardian. The code is read out one character at a
time: *"F, H, 2, 9. Then: M, R, 4, 7."*

**Say:** the alphabet has no B, D, E, G, P, T, V or Z, because they all rhyme,
and no I, L, O, S, 0, 1 or 5, because they are confusable. It is eight
characters rather than six because any signed-in account can look a code up, so
the code space is the only thing between a stranger and enumeration.

On the guardian phone, **Create account** with the code. It lands on the
guardian dashboard. (The testers' version stopped on the form, and a second
press said the email was already taken.) They are now paired.

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

- **Users** — press **Blind**, then **Guardians**: the counts are on the
  chips. **Add account** for a made-up tester: no password is chosen, the
  person gets an email to set one. **Edit** them, then **Remove** them, and
  read the dialog out: it lists exactly what is deleted, and says the sign-in
  record stays.

Close on the scope table in [`SCOPE.md`](SCOPE.md).

---

## Round 2 — what the testers asked for (6 min)

Hands-free is on by default on Android. Do not touch **Tap to speak** in this
part; that is the point.

1. **Read Text by voice.** Say *"read"*. Point the phone at a printed page and
   say *"basahin"*. While it reads, say *"pause"*, *"continue"*, *"next"*.
   **Say:** the page is heard by the same microphone, and its words are not
   taken as commands — a line that starts with "Next" does not skip a line.
2. **The buttons read as words.** Turn the phone's text size to the largest.
   Pause, Say that again and Next line stack; no label breaks mid-word.
3. **Directions, turn by turn.** On the dashboard say *"take me to"* and a
   shop nearby. It offers what it found one at a time — *"Jollibee, Paseo del
   Congreso, Malolos, about 600 metres away. Say yes to go there, next for
   another, or no"* — say *"next"*, then *"yes"*. Scan opens with the route
   summary, and then *"In about 50 metres, turn left onto Mabini Street."*
   **Say:** the route is OpenStreetMap's, free and best effort, and the
   credit is on screen.
4. **Now airplane mode.** Say *"take me home"*. Home is saved, so it still
   starts: *"I could not get a walking route to Home, because there is no
   internet connection. Until then, I will give the straight-line direction,
   which can cross roads and buildings."* **Say:** a failure is named, and
   the fallback is said to be one.
5. **A friend.** Turn on *Recognise people I know* in Settings. On Scan, with
   a teammate who agrees in front of the camera, say *"hello friend Sam"*. The
   phone asks **Sam**, out loud; Sam says *"yes"*. Hold still for two seconds:
   *"Saved Sam."* Straight after: *"Your friend Sam is in front of you."* A
   friend is named once a minute at most, so for the next part Sam waits a
   minute across the room, then walks up to the phone: *"Your friend Sam is
   approaching."* **Say:** a face is saved only on its owner's
   yes, kept on this phone as numbers, never a picture, never uploaded — and
   turning the switch off deletes it, which you can show next.
6. **Who is here.** Say *"who is here"* with Sam in view. Then *"forget
   Sam"*, and *"yes"*.

---

## If something fails live

- **The guardian phone does not alert.** Say so, and explain why: server-side
  push needs Cloud Functions, which need a paid plan. The guardian app holds a
  Firestore listener instead, which works while the app is open. Open it and
  fire again. `functions/index.js` is the production path, written and waiting.
- **Scanning finds nothing.** The model is YOLO11n on COCO's eighty classes;
  point the camera at a person or a chair. If it still finds nothing, use the
  Repeat button to show the guidance path works and move on — do not debug
  live.
- **The web dashboard is empty.** It says "No sessions yet" because nothing has
  been recorded with history consent on. That is the correct empty state, and
  worth saying: the screen it replaces would have shown zeroes that read as
  measurements.
- **Hands-free does not seem to hear.** Check Settings says *Hands-free voice:
  on*, and that the phone has a speech recogniser (the Android emulator does
  not). Tap to speak still works; use it and move on.
- **No walking route.** routing.openstreetmap.de is run by volunteers and may
  be slow or down. The app says so and gives the straight line — that *is* the
  demo of the fallback. Do not retry live.
- **"Recognising people is not available on this phone yet."** The two face
  models are not in this build; see `VISION.md`. Say so, show People I know
  and the consent switch, and move on.
- **Sam is not recognised.** The match threshold has not been calibrated on
  this camera. Good light, face the phone, about an arm's length. Two tries,
  then move on.
- **The verification email does not arrive.** Check spam. The demo can use an
  account made before the cutoff, which is not held.
