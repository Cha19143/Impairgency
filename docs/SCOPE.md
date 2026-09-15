# Scope

Put this on a slide unedited. A defended boundary scores; an undefended feature
claim does not.

## Built

| Requirement | Where |
|---|---|
| Nearby object detection, audio feedback | §2.A.1 |
| Environment detection and voice alerts | §2.A.3 |
| Real-time location sharing | §2.A.4 |
| SOS: alarm, call, location, guardian alert | §2.A.5 |
| Travel recording and journey review | §2.A.7 |
| Routine learning | §2.B.1 |
| Environment learning | §2.B.2 |
| Voice interface — all six named functions | §2.C |
| Guardian real-time location | §3.1 |
| Guardian SOS alerts | §3.2 |
| Large text, large buttons, high contrast, screen readers | §4 |
| Admin: user management, analytics, session review | §1.1–§1.3 |
| Admin: filter by blind, colour blind, guardian; add, edit and remove accounts | §1.2 |
| Admin dashboard delivered as **web** | Overview, §6 |
| Privacy, consent, reliability, safety notice | §7 |
| **Familiar person recognition — narrowed.** Only people who said yes, out loud, when they were saved. Kept on the phone as numbers, never as pictures, never uploaded or backed up. Deleted when the consent is turned off, and at sign-out. Anyone else is compared and discarded in the same frame | §2.A.6, §2.B.3 |
| **Walking directions, turn by turn**, from OpenStreetMap's free router. Best effort: when there is no route (no connection, no path on the map, the service down), the app says which and gives the straight-line direction instead | Smart assistance, Scan |
| **Hands-free voice.** The microphone reopens by itself on the main, scan, read and where-to screens; the app's own speech is not heard as a command; a Settings switch turns it off | §2.C |
| **New accounts confirm their email** before they reach the app. Accounts made before the cutoff are not held | §7 |

## Deliberately not built

Each of these was reachable. Each was declined for a reason, and the reason is
the point.

| Not built | Why |
|---|---|
| **Recognising anyone who has not agreed** | The first scope table declined familiar person recognition outright, because a stranger on the street cannot consent. The testers asked for it, and it is now built on exactly that line: a face is saved only after its owner answers yes, out loud, with the phone in front of them. Recognising people from contacts, photos or a guardian's list - anyone who was not asked - stays out. |
| **Bluetooth / IoT hardware** §5 | No device exists to pair with. A BLE stack written against imaginary hardware is untestable code. The architecture keeps hardware gating nothing, so it can be added without touching the flow. |
| **Emergency and fire exit guidance** §2.A.2 | Requires indoor floor-plan data. No public source provides it for the buildings these users occupy. Naming this beats a feature that silently never fires. |
| **Video session recording** §1.1 | Substituted by an event timeline that serves the requirement's stated purpose — *"analyse navigation performance and identify possible system improvements"* — at no storage cost and none of the consent burden of recording a blind person's home. |
| **Guaranteed routes** | Walking routes come from routing.openstreetmap.de, run by volunteers with no service promise, and Photon for place names. A commercial routing API with an uptime guarantee needs a key and a card. When the free service fails, the straight line takes over and says so. |
| **Server-side push fan-out** | Cloud Functions need a billing account. The guardian app holds a Firestore listener and raises a local notification instead: reliable on Android, time-limited on iOS. `functions/index.js` is the production path, written and waiting. |
| **iOS remote push** | Needs a $99/year Apple Developer membership. Android is the demo platform. iOS still does alarm, phone call, location and scan. |
| **Deployed Storage rules** | A Cloud Storage bucket requires the Blaze plan. Nothing in scope stores a file, so there is no bucket and nothing to protect. `storage.rules` is written and **verified anyway** on the Storage emulator, which provisions a local bucket for free — that test found a real defect the console would have hidden. Free tooling proved a rule that a paid plan would have been needed to deploy. |

## Partial, and honest about it

| | |
|---|---|
| **Stairs detection** §2.A.3 | Generic object detection covers some of it. Stairs specifically is a fall risk and deserves a dedicated class or a floor-plane heuristic, with a confidence threshold that stays silent rather than guessing. |
| **Detection performance** §1.3 | Counts and positioning quality, not accuracy. Accuracy needs labelled ground truth and nobody has labelled it. The dashboard says so on screen. |
| **Crash and response-time monitoring** §1.4 | Reported to Firebase; the dashboard links to the console rather than mirroring it, because reading it back needs a service account and therefore a paid plan. |
| **Friend recognition accuracy** §2.A.6 | The match threshold is MobileFaceNet's published starting point, not a measurement on this app's camera. It needs calibrating with people who agree to take part, at walking distances and in daylight and indoors, before anyone relies on it. The two face models are downloaded separately; a build without them says recognition is not available. See [`VISION.md`](VISION.md). |
| **Email verification** §7 | Enforced by the app, not by the security rules: rules cannot see when an account was created, so they cannot tell a grandfathered account from a new one. The one exception is claiming an invitation, which keys off the email address and does require it confirmed. |
| **Removing an account** §1.2 | Removes the profile, links, codes and history, and locks the account out through the rules. The Firebase sign-in record itself stays: deleting it needs the Admin SDK, which needs Cloud Functions and the Blaze plan. The dashboard says so when it removes someone. |

## What the numbers are

```
Requirements built            16 of 21
Declared out of scope          5, each with a reason
Flutter tests               1136
Security rules tests          90
Browser tests                 12
Platforms building             2 of 3 checked this round: Android and web.
                                        iOS not rebuilt - the build Mac's Xcode
                                        licence has not been accepted.
Contrast pairs at WCAG AA      8 of 8   (three clear AAA)
```

## The three things worth saying out loud

1. **The app never claims success it did not have.** An SOS receipt names every
   leg, and says "nobody was reached" when nobody was. Tests assert it never
   says "help is on the way".

2. **Consent is enforced by the server, not by hiding a button.** Revoking
   location consent stops a guardian reading a position. Recording history is a
   *separate* consent from sharing location, because being findable and being
   logged are different decisions.

3. **The learning features involve no model.** Routine learning, environment
   learning, travel recording and the dashboard's frequent-locations panel are
   four aggregations over one collection of timestamped positions. It is
   explainable in one slide, and it is honest: the app has counted something,
   not learned something.
