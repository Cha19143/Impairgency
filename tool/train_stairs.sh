#!/usr/bin/env bash
# Trains the stairs detector and puts it where the app loads it.
#
#   tool/fetch_stairs.py --negatives ~/Pictures/floors   # first: the data
#   tool/train_stairs.sh                                  # then: this
#   DEVICE=0 EPOCHS=60 tool/train_stairs.sh               # a CUDA GPU (Colab)
#
# A single-class YOLO11n, from the same yolo11n.pt the COCO model was
# exported from, at 416 - small enough to run beside the COCO model every
# other frame. On a Colab T4 about one to two hours; on the Mac's GPU (the
# default, DEVICE=mps) longer.
#
# Needs `pip install ultralytics`. Ultralytics downloads yolo11n.pt itself on
# the first run (about 5 MB, AGPL-3.0 like the model already shipped - see
# docs/VISION.md). The trained file inherits that licence.
#
# Afterwards, before the app may say "Stop" for stairs:
#   tool/eval_detector.py --stairs --fetch --negatives ~/Pictures/floors
# and record the table in docs/VISION.md, "Stairs".
set -euo pipefail
cd "$(dirname "$0")/.."

DATA=${DATA:-build/stairs-data/stairs.yaml}
DEVICE=${DEVICE:-mps}
EPOCHS=${EPOCHS:-60}
BATCH=${BATCH:-32}
RUNS=build/stairs-runs
OUT=assets/models/yolo11n_stairs.tflite

if [ ! -f "$DATA" ]; then
  echo "No dataset at $DATA. Run tool/fetch_stairs.py first." >&2
  exit 1
fi
if ! command -v yolo >/dev/null 2>&1; then
  echo "yolo is not installed: pip install ultralytics" >&2
  exit 1
fi

yolo detect train model=yolo11n.pt data="$DATA" imgsz=416 epochs="$EPOCHS" \
  batch="$BATCH" device="$DEVICE" project="$RUNS" name=stairs exist_ok=True

BEST="$RUNS/stairs/weights/best.pt"
# The same export as the COCO model: LiteRT, float16 weights, planar input.
yolo export model="$BEST" format=tflite imgsz=416 half=True

EXPORTED=$(ls "$RUNS"/stairs/weights/best_saved_model/*float16.tflite | head -1)
python3 tool/tflite_shapes.py "$EXPORTED"
# What lib/data/stairs_detector_io.dart checks at load: [1, 3, 416, 416] in,
# [1, 5, anchors] out. A model of any other shape is refused there, so it is
# refused here first.
python3 - "$EXPORTED" <<'PY'
import subprocess, sys
shapes = subprocess.run(['python3', 'tool/tflite_shapes.py', sys.argv[1]],
                        capture_output=True, text=True, check=True).stdout
if '[1, 3, 416, 416]' not in shapes or '[1, 5, ' not in shapes:
    sys.exit(f'Not the shape the app reads:\n{shapes}')
PY

cp "$EXPORTED" "$OUT"
echo
echo "$OUT"
shasum -a 256 "$OUT"
ls -l "$OUT"
echo
echo "Next: add $OUT to pubspec.yaml's assets, measure it with"
echo "tool/eval_detector.py --stairs, and record the hash and the table in"
echo "docs/VISION.md."
