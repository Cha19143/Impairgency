# The detector

The scan screen runs **YOLO11n**, COCO's eighty classes, at 320×320, on the
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
yolo export model=yolo11n.pt format=tflite imgsz=320
```

`yolo11n.pt` comes from `github.com/ultralytics/assets`. The export runs
through Ultralytics' LiteRT path, which keeps PyTorch's channel-first layout —
hence the planar `[1, 3, 320, 320]` input, which is *not* what the older
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
