# The detector

The scan screen runs **YOLO11n**, COCO's eighty classes, at 320×320, on the
CPU through `tflite_flutter`. It replaces the SSD MobileNet ported from
`cprwire`.

| | before | now |
|---|---|---|
| Model | SSD MobileNet v1 | YOLO11n |
| Asset | `ssd_mobilenet.tflite`, 4.2 MB | `yolo11n.tflite`, 10.2 MB |
| Input | `[1, 300, 300, 3]` uint8, interleaved | `[1, 3, 320, 320]` float32 0–1, planar |
| Output | four tensors, thresholded and de-duplicated by the graph | one tensor, `[1, 84, 2100]`, raw |
| Classes | 90, COCO's label map with its gaps | 80, COCO's classes |
| Frame fitted | stretched to the square | letterboxed into it |
| COCO mAP50-95 | ≈ 19 | ≈ 33 at this size |

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
changing `imgsz=` and dropping in the new file is the whole change. 320 is a
deliberate floor rather than a default: obstacles a walking user needs to be
warned about are large in frame, and the cost of 640 is four times the
arithmetic on the thread that draws the screen.

## What it does not do

- **It runs on the UI isolate**, as the SSD did before it, throttled to one
  inference every 350 ms. `tflite_flutter` offers `IsolateInterpreter`, and
  moving inference behind it is the next thing to do here — it wants a device
  to verify on, which is why it has not been done blind.
- **Eighty classes is eighty classes.** Stairs, kerbs, glass doors and
  overhanging branches are not among them, and §2.A.3's stairs requirement is
  still open. The safety notice says so, and must keep saying so.
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
