# The detector

The scan screen runs **YOLO11n**, COCO's eighty classes, at 640×640, on the
CPU through `tflite_flutter`. It replaces the SSD MobileNet ported from
`cprwire`.

| | before | now |
|---|---|---|
| Model | SSD MobileNet v1 | YOLO11n |
| Asset | `ssd_mobilenet.tflite`, 4.2 MB | `yolo11n.tflite`, 10.3 MB |
| Input | `[1, 300, 300, 3]` uint8, interleaved | `[1, 3, 640, 640]` float32 0–1, planar |
| Output | four tensors, thresholded and de-duplicated by the graph | one tensor, `[1, 84, 8400]`, raw |
| Classes | 90, COCO's label map with its gaps | 80, COCO's classes |
| Frame fitted | stretched to the square | letterboxed into it |
| Runs on | the UI isolate | a background isolate |

## What it actually finds

Not "it detected a bus in a photograph of a bus". `tool/eval_detector.py`
runs the shipped pipeline over 846 annotated Open Images photographs — the
same letterbox, the same flat NCHW input, the same class-agnostic suppression,
the same thresholds — and reports **recall stratified by how big the object is
in frame**, because that is the app's own question. `guidanceFor` speaks about
the largest, most central thing; `extent` over 0.30 is "close", over 0.55 is
"Stop". Whether the detector finds a chair thirty metres away is not the test.

Recall rather than mAP, deliberately: Open Images does not label every object
in every image, so precision over the whole set is meaningless and recall is
unaffected. Recall is also the number that matters here — a missed obstacle is
somebody walking into it, a spurious one is a sentence they ignore. Precision
is reported only over images where the class in question is annotated, where
Open Images *is* exhaustive.

| | 320, score ≥ 0.5 | **640, score ≥ 0.35** |
|---|---|---|
| very close (>0.55) | 74% | **78%** |
| close (0.30–0.55) | 55% | **76%** |
| **close or nearer** | **68%** | **77%** |
| everything, all sizes | 48% | 65% |
| precision | 86% | 78% |

Two changes bought that, and both were chosen by running the numbers rather
than by taste:

**640 rather than 320.** Four times the arithmetic, and it dominates the
smaller input at every threshold — 640 at 0.5 finds more than 320 at 0.35 does,
and is more precise while doing it. The classes it rescued are the ones this
app is for: person 31% → 54%, chair 32% → 58%, traffic light 41% → 77%,
bicycle 44% → 57%, bench 22% → 44%.

**A mention threshold of 0.35, and a separate one of 0.5 for "Stop".** The
lower bar costs about eight points of precision and buys five of recall, which
is the right way round when the failure it prevents is a collision. But "Stop"
is the one thing this app says that halts somebody mid-step in a street, and a
person stopped for nothing three times stops believing the fourth — so a weak
detection is enough to be named and not enough to be shouted. `kMinScore` and
`kUrgentScore` in `core/vision/detection.dart`.

**And the camera was handing over 320×240.** `ResolutionPreset.low` is 240p, so
a 640 model was spending most of its input on upscaled blur — worth two points
of recall on nearby objects and four across everything. It is now `medium`,
720×480, which is close to free: `_fillInput` walks the model's input and
samples back into the camera frame, so a larger frame does not lengthen that
loop. The evaluation simulates this rather than assuming it away, which is why
`--camera-frame` defaults to a camera-sized image and not to the
1024-pixel photograph on disk.

Reproduce any of it, or ask what a different setting would have done:

```bash
tool/eval_detector.py --fetch              # first run, builds the set
tool/eval_detector.py --min-score 0.5      # what the old bar would have found
tool/eval_detector.py --camera-frame 320   # what ResolutionPreset.low saw
```

## Why the code around it changed as much as it did

An SSD graph ends in a `TFLite_Detection_PostProcess` node. It hands back
boxes, classes, scores and a count, already thresholded and already
de-duplicated. YOLO11 ends at the head: one tensor holding every anchor it
has, with no threshold and no non-maximum suppression anywhere in it. All of
that had to be written, and it is in [`lib/core/vision/yolo.dart`](../lib/core/vision/yolo.dart)
rather than beside the camera, because every mistake worth making lives in that
arithmetic and none of them crash. A transposed index, a centre read as a
corner, suppression that keeps the wrong box — each one mis-describes the room
to someone who cannot check. They are unit tested against hand-built tensors in
`test/core/vision/yolo_test.dart`.

Two decisions in there are deliberately not Ultralytics' defaults:

**Suppression ignores classes.** Ultralytics suppresses within a class, which
is right for counting things and wrong for talking about them. A chair the
model half-reads as a bench is one thing to walk into, and `guidanceFor` names
a second object whenever its label differs from the first — so class-aware
suppression produces *"Stop. chair right in front of you. bench ahead"* for a
single obstacle. It costs little: suppression needs 0.45 overlap, and a person
standing in front of a bus overlaps it by their own area over the bus's. Small
things in front of big things survive, which is the case that matters.

**The frame is letterboxed, not stretched.** The SSD version mapped the whole
frame onto the square, which is easier and was wrong in a way nothing would
have reported. Stretching leaves *direction* intact, because the squeeze is
linear — but `Detection.extent`, the larger side of a box, is the only depth
cue one camera has, and a 4:3 frame stretched to a square inflates every
horizontal box by a third. That is the difference between "chair ahead" and
"Stop, right in front of you" for something across the room, which is exactly
the failure the safety notice promises the app does not commit.

## Where the model came from

Not downloaded from a third party. Exported here, from Ultralytics' own
published weights:

```bash
pip install ultralytics
yolo export model=yolo11n.pt format=tflite imgsz=640
```

`yolo11n.pt` comes from `github.com/ultralytics/assets`. The export runs
through Ultralytics' LiteRT path, which keeps PyTorch's channel-first layout —
hence the planar `[1, 3, 640, 640]` input, which is *not* what the older
`onnx2tf` route produces and not what most Flutter examples of this assume.

`assets/models/labels.txt` is written out of the same weights' `names` map, in
index order, so the labels cannot drift from what the model predicts.
`ScanService.loadModel` refuses to start if the count disagrees with the
model's class dimension, because the failure otherwise is every box captioned
with the wrong object.

The export was checked against Ultralytics' own predictions on `bus.jpg` at the
same size: same four objects, box centres agreeing to 0.01 of the frame.

### Re-exporting it

The shapes are read off the interpreter at load, not written down in Dart, so
changing `imgsz=` and dropping in the new file is the whole change. Measure
before and after with `tool/eval_detector.py`; the table above is what the
current asset scores.

### Where it runs

On a background isolate, via `IsolateInterpreter`. At 640 a single inference
is 40 ms on four desktop cores and several times that on a handset, which is
too long to hold the isolate that answers platform messages — the camera
delivers frames through one and the speech goes out through another, so
blocking it does not merely stutter the preview, it delays "Stop".

If the isolate cannot be started, `ScanService` says so in the log and runs
inference inline instead. That fallback is the code that shipped before, and
a scan screen that runs slowly is worth a great deal more than one that does
not run.

## What it does not do

- **Kerbs, glass doors, potholes and overhanging branches** are not among the
  classes and are not detected. The safety notice says so, and must keep
  saying so.
- **Stairs** are not a COCO class either. A separate heuristic looks for them,
  and is off by default: see "Stairs" below.
- **One camera has no depth.** Nearness is inferred from box size. A poster of
  a person is a person.

## Licence

Ultralytics publish YOLO11 and its weights under **AGPL-3.0**. Shipping this
APK is distribution: it means either releasing this application's source under
AGPL-3.0 as well, or holding an Ultralytics Enterprise licence. This repository
carries no licence file yet, so that decision is still open and has to be made
before the app is handed to anyone outside the team.

If AGPL is not acceptable and a licence is not being bought, the way out is a
different detector rather than a different file name — an Apache-2.0 or
BSD-licensed model (the previous SSD MobileNet, or NanoDet-Plus) behind the
same `ScanService`. The decode in `core/vision/yolo.dart` is specific to
YOLO's output shape; everything else in the scan path is not.

---

# Stairs

A missed step is a fall, and YOLO11n has no class for stairs. So Scan can run a
second, much simpler look at the floor: `core/vision/stairs.dart`, ported from
PR #74, where it was written against the old SSD pipeline and never tried on a
phone.

**It is off by default.** Builds switch it on with
`--dart-define=STAIRS_WARNINGS=true`. The reason is measured, below.

## What it looks for

Regular horizontal banding in the lower part of the frame. That is what the
nosings of a flight look like to one camera. Four or more edges must be found.
They must be spaced regularly *in ratio*, so a flight is still regular after
perspective shrinks the far treads, and they must cross most of the width. The
result is a confidence from 0 to 1. It is not a probability: nothing here was
calibrated against labelled photographs.

## How it runs

- **The grid.** The brightness grid is 300 by 300: the grid its thresholds and
  tests were tuned at, since tread spacing is measured in grid rows.
  `fillStairsGrid` fills it from the camera's brightness plane through
  `YuvFrame.lumaAt`, turned upright. Only the part the search reads is sampled:
  the lower 55% of the frame, 15% in from each side.
- **When.** In `ScanService`, inside the same busy window as YOLO and the face
  pass, so closing the screen waits for it. At most every 500 ms, on the
  isolate that draws the screen.
- **Between searches.** A frame carries the last reading for up to a second,
  so the status and the speech do not flip between "stairs" and "clear".
- **With the objects.** The reading travels with that frame's objects as one
  `ScanFrame`.

## What it says

*"Stop. Stairs ahead."*: never up or down, which one camera cannot tell apart.
It goes through `guidanceFor` and `shouldSpeak`:
- It is urgent, so it comes at hazard priority with a buzz, and repeats only
  after `kHazardRepeat`.
- It is said alone, ahead of any object, except an object urgent in its own
  right: a car right in front is named as a car.
- Below 0.6 it says nothing.
- The guardian's feed shows "Obstacle: stairs", as for any urgent warning, and
  only with activity consent.

## Why it is off: what it cannot tell apart

Seen from above, a flight is a row of evenly receding edges, and so is a tiled
floor. In its own tests (`test/core/vision/stairs_test.dart`, "what banding
cannot tell apart, measured"), a floor of 30 cm tiles scores **0.86** and a
zebra crossing **0.75**. Both are over the threshold, so both would be
announced as stairs. Escalators and striped rugs are the same kind of case.

A warning that says "Stop" on every tiled floor in a mall or a hospital teaches
someone to ignore "Stop". That is exactly what `kUrgentScore` exists to
prevent for objects, and the next "Stop" may be a car.

## Before turning it on

Build with the flag and hold the phone as users do. Go:
- down and up real flights, indoors and out, in daylight and under lights;
- across tiled floors, a zebra crossing, an escalator and a striped rug.

Note each time it spoke and each time it should have. Turn it on by default
only if it warns on stairs from far enough away to stop, and stays quiet on
floors. If floors still trigger it, it needs more than banding before it
speaks: the phone's tilt, or a trained class.

---

# Faces

Recognising friends (§2.A.6, §2.B.3) runs two more small models through the
same `tflite_flutter`, on their own background isolates, and only when asked:
a person near enough to recognise in the frame (YOLO's box, a fifth of the
frame or more), or a friend being saved. Never more often than every 400 ms.

| | Detector | Recogniser |
|---|---|---|
| Model | MediaPipe BlazeFace, short range | MobileFaceNet |
| Asset | `assets/models/face_detection_short_range.tflite`, about 230 KB | `assets/models/mobilefacenet.tflite`, a few MB |
| Input | `[1, 128, 128, 3]` float32, −1 to 1 | `[1, 112, 112, 3]` float32, `(x − 127.5) / 128` |
| Output | `[1, 896, 16]` boxes and six landmarks, `[1, 896, 1]` scores | `[1, N]`, one face as N numbers |
| Decoded in | `core/vision/blazeface.dart` — anchors, sigmoid, weighted merge at IoU 0.3, MediaPipe's own settings | `core/vision/faces.dart` — unit length, cosine similarity |

Both are **checked at load**, by shape, as the detector is. The recogniser's
output length is read off the model, so a 128- or 192-number variant both work.

**The detector is in; the recogniser is not yet.** Each file is added only with
the team's agreement on that file, its source and its licence. A build without
both runs normally: the scan screen says *"Recognising people is not available
on this phone yet"* when asked, and nothing else changes.

| File | Source | Size | Checked |
|---|---|---|---|
| `face_detection_short_range.tflite` | Google, `https://storage.googleapis.com/mediapipe-assets/face_detection_short_range.tflite` | 229,032 bytes, SHA-256 `3bc182eb9f33925d9e58b5c8d59308a760f4adea8f282370e428c51212c26633` | MD5 matches Google's; `input [1,128,128,3]`, `regressors [1,896,16]`, `classificators [1,896,1]`, all float32 |
| `mobilefacenet.tflite` | Proposed: `MCarlomagno/FaceRecognitionAuth`, `assets/mobilefacenet.tflite` (repository BSD-3-Clause, archived) | 5,233,552 bytes | Not downloaded. Check `input [1,112,112,3]` and `[1,N]` output with `tool/tflite_shapes.py` before adding |

`tool/tflite_shapes.py` reads a model's tensors without TensorFlow; it reports
YOLO11n as `[1,3,640,640]` in and `[1,84,8400]` out, as `ScanService` expects.

## How a face is read

1. The top 45% of a person's box is squared up and sampled into 128×128
   (`core/vision/yuv_frame.dart`, straight from the camera's YUV planes, turned
   upright as the YOLO path does).
2. BlazeFace finds the face and its eyes, nose and mouth.
3. The face is **aligned**: one rotation, one scale and one shift that put
   those four points on ArcFace's 112×112 template, fitted by least squares
   (`core/vision/face_align.dart`). A tilted or off-centre crop changes the
   numbers more than a different person does, so this step is not optional.
4. MobileFaceNet turns the aligned face into numbers, made unit length.
5. The numbers are compared with each saved friend's five views
   (`bestMatch`). Nothing is kept for a face that matches nobody.

## The thresholds, and why they are not finished

- **Match at cosine 0.62, and 0.08 clear of the next friend.** A starting point
  from MobileFaceNet's published results, not a measurement on this camera.
- **Calibrate before relying on it.** With 3–5 people who agree to take part:
  save each, then log (debug builds only) the similarity of every face seen to
  every friend, at 0.5, 1, 2 and 3 metres, in daylight and indoors. Pick the
  threshold that gives **no match between different people**; missing a
  friend is a sentence not said, and naming the wrong person is worse.
- **Saving** takes five views within six seconds: one face only, at least 12%
  of the frame wide, tilted no more than 25°, all five agreeing at 0.55 or
  better, and not already saved as someone else.
- **Announcing** needs two matches within 1.5 s; once a minute per friend; 8 s
  between any two names; information priority, so a hazard always comes first.
  "Approaching" is the face growing 20% within 2.5 s.

## What is kept

Five lists of numbers per friend, their name, and when they were saved, in one
file per account: `<app support>/faces/<account>.json`. Never a picture.
Excluded from Android backup and device transfer
(`android/app/src/main/res/xml/data_extraction_rules.xml`, `backup_rules.xml`)
and from iOS backup (`BackupChannel` in `AppDelegate.swift` marks the folder).
Deleted when *Recognise people I know* is turned off, at sign-out, and one at a
time from People I know. Nothing about who was seen goes to the guardian, the
activity feed or the history.

## Licences

- **BlazeFace** is published by Google under **Apache-2.0** (MediaPipe).
- **MobileFaceNet**: the architecture and most published code are Apache-2.0 or
  MIT, but the widely shared weights were trained on **MS-Celeb-1M**-derived
  data (MS1M / MS1MV2), released for **non-commercial research use**. That is
  compatible with a capstone demonstration and not with a product. Record the
  exact file's source and terms here when it is chosen, next to YOLO11's AGPL
  note above.

