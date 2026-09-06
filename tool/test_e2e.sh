#!/usr/bin/env bash
# Runs the admin dashboard's browser tests against the local emulators.
#
#   tool/test_e2e.sh
#
# Builds the web app pointed at the emulators, serves it from the hosting
# emulator, seeds an admin and some sessions, and drives the result in Chromium.
# No Firebase project and no network - the emulators run against a demo project
# id, the same one tool/test_rules.sh uses, so the dashboard is read through the
# real firestore.rules. Requires a JDK 21+ for the Firestore emulator.
#
# NOTE: this leaves build/web pointing at the emulators. Run a plain
# `flutter build web` before `firebase deploy --only hosting`.
set -euo pipefail
cd "$(dirname "$0")/.."

. tool/lib/require_jdk21.sh

# Flutter is often not on PATH on a fresh shell.
if ! command -v flutter >/dev/null 2>&1; then
  for candidate in "$HOME/development/flutter/bin" "$HOME/flutter/bin" /opt/homebrew/bin; do
    if [ -x "$candidate/flutter" ]; then
      export PATH="$candidate:$PATH"
      break
    fi
  done
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH. Add the SDK's bin directory and try again." >&2
  exit 1
fi

[ -d test/e2e/node_modules ] || npm --prefix test/e2e install --silent
# Playwright needs its own browser build; a no-op once it is there.
npx --prefix test/e2e playwright install chromium >/dev/null

# The accessibility tree the tests read only exists in an emulator build, and
# --no-web-resources-cdn keeps CanvasKit local so a run needs no network.
flutter build web --dart-define=USE_EMULATOR=true --no-web-resources-cdn

echo
echo "build/web now points at the emulators - rebuild before deploying."
echo

exec firebase emulators:exec --only auth,firestore,hosting --project demo-impairgency \
  "npm --prefix test/e2e test"
