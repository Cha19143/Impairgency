#!/usr/bin/env bash
# Builds the depth device-check APK: the tester build plus the MiDaS depth
# model, with the depth warnings switched on. Not for testers.
#
#   tool/build_depth_check.sh
#
# pubspec.yaml names each model it bundles so the 66 MB depth model can never
# ride along by accident. This adds it to a copy of pubspec.yaml for one
# build and puts the original back, whatever happens.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL=assets/models/model_opt.tflite
if [ ! -f "$MODEL" ]; then
  echo "$MODEL is not here. See docs/VISION.md, \"Depth\", for where it comes from." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  export PATH="$HOME/development/flutter/bin:$PATH"
fi

cp pubspec.yaml pubspec.yaml.depth-check-backup
trap 'mv pubspec.yaml.depth-check-backup pubspec.yaml' EXIT

python3 - "$MODEL" <<'PY'
import sys
model = sys.argv[1]
text = open('pubspec.yaml').read()
anchor = '    - assets/models/yolo11n.tflite\n'
assert anchor in text, 'pubspec.yaml no longer lists the models the way this script expects'
open('pubspec.yaml', 'w').write(text.replace(anchor, anchor + f'    - {model}\n', 1))
PY

flutter build apk --release --dart-define=DEPTH_WARNINGS=true
echo
echo "Depth-check build: build/app/outputs/flutter-apk/app-release.apk (not for testers)."
