#!/usr/bin/env bash
# Trains the stairs detector and puts it where the app loads it.
#
#   tool/fetch_stairs.py --negative-label "Tile flooring" ...   # the data
#   PATH="$PWD/build/stairs-venv/bin:$PATH" tool/train_stairs.sh   # this
#   DEVICE=0 EPOCHS=60 tool/train_stairs.sh               # a CUDA GPU (Colab)
#
# A single-class YOLO11n, from the same yolo11n.pt the COCO model was
# exported from, at 416 - small enough to run beside the COCO model every
# other frame. On a Colab T4 about one to two hours; on the Mac's GPU (the
# default, DEVICE=mps) under an hour.
#
# Needs, in one Python 3.13 environment (build/stairs-venv here):
#   pip install ultralytics "litert-torch>=0.9" "ai-edge-litert>=2.1.4"
# litert-torch pins its own torch, so torchvision has to follow it (torch
# 2.13 wants torchvision 0.28); `pip check` says when they disagree.
# Ultralytics downloads yolo11n.pt itself on the first run (about 5 MB,
# AGPL-3.0 like the model already shipped - see docs/VISION.md). The trained
# file inherits that licence.
#
# Afterwards, before the app may say "Stop" for stairs:
#   tool/eval_detector.py --stairs --fetch --per-class 1000 \
#     --negative-label "Tile flooring" ...
# and record the table in docs/VISION.md, "Stairs".
set -euo pipefail
cd "$(dirname "$0")/.."

DATA=${DATA:-build/stairs-data/stairs.yaml}
DEVICE=${DEVICE:-mps}
EPOCHS=${EPOCHS:-60}
BATCH=${BATCH:-32}
# Absolute, because Ultralytics 8.4 files a relative project under
# runs/detect/ in the working directory.
RUNS="$PWD/build/stairs-runs"
# Where Ultralytics puts yolo11n.pt when it fetches it: under build/, not in
# the repository.
WEIGHTS=${WEIGHTS:-$RUNS/yolo11n.pt}
OUT=assets/models/yolo11n_stairs.tflite

if [ ! -f "$DATA" ]; then
  echo "No dataset at $DATA. Run tool/fetch_stairs.py first." >&2
  exit 1
fi
if ! command -v yolo >/dev/null 2>&1; then
  echo "yolo is not installed: pip install ultralytics" >&2
  exit 1
fi

yolo detect train model="$WEIGHTS" data="$DATA" imgsz=416 epochs="$EPOCHS" \
  batch="$BATCH" device="$DEVICE" project="$RUNS" name=stairs exist_ok=True

BEST="$RUNS/stairs/weights/best.pt"
# The same export as the COCO model: Ultralytics' LiteRT path (format=tflite
# is its old name), float32 weights - LiteRT's GPU delegate runs them in
# float16 by itself - a planar input, and box coordinates as fractions of
# the input. It writes best.tflite beside best.pt.
yolo export model="$BEST" format=litert imgsz=416

EXPORTED="$RUNS/stairs/weights/best.tflite"
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
