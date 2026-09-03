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
| Admin dashboard delivered as **web** | Overview, §6 |
| Privacy, consent, reliability, safety notice | §7 |

## Deliberately not built

Each of these was reachable. Each was declined for a reason, and the reason is
the point.

| Not built | Why |
|---|---|
| **Familiar person recognition** §2.A.6, §2.B.3 | It processes the biometrics of third parties who are never asked. §7 requires consent for recognition of people, and a stranger on the street has no way to give it. This is the ethically correct answer, not the convenient one. |
| **Bluetooth / IoT hardware** §5 | No device exists to pair with. A BLE stack written against imaginary hardware is untestable code. The architecture keeps hardware gating nothing, so it can be added without touching the flow. |
| **Emergency and fire exit guidance** §2.A.2 | Requires indoor floor-plan data. No public source provides it for the buildings these users occupy. Naming this beats a feature that silently never fires. |
| **Video session recording** §1.1 | Substituted by an event timeline that serves the requirement's stated purpose — *"analyse navigation performance and identify possible system improvements"* — at no storage cost and none of the consent burden of recording a blind person's home. |
| **Server-side push fan-out** | Cloud Functions need a billing account. The guardian app holds a Firestore listener and raises a local notification instead: reliable on Android, time-limited on iOS. `functions/index.js` is the production path, written and waiting. |
| **iOS remote push** | Needs a $99/year Apple Developer membership. Android is the demo platform. iOS still does alarm, phone call, location and scan. |

## Partial, and honest about it

| | |
|---|---|
| **Stairs detection** §2.A.3 | Generic object detection covers some of it. Stairs specifically is a fall risk and deserves a dedicated class or a floor-plane heuristic, with a confidence threshold that stays silent rather than guessing. |
| **Detection performance** §1.3 | Counts and positioning quality, not accuracy. Accuracy needs labelled ground truth and nobody has labelled it. The dashboard says so on screen. |
| **Crash and response-time monitoring** §1.4 | Reported to Firebase; the dashboard links to the console rather than mirroring it, because reading it back needs a service account and therefore a paid plan. |

## What the numbers are

```
Requirements built            15 of 21
Declared out of scope          6, each with a reason
Flutter tests                427
Security rules tests          64
Platforms building             3 of 3
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
