#!/usr/bin/env bash
# Runs the Firestore and Storage security rules suites against the local emulator.
#
#   tool/test_rules.sh
#
# No Firebase project or network needed - the emulator runs against a demo
# project id. Requires a JDK 21+; the emulator will not start on older Java.
set -euo pipefail
cd "$(dirname "$0")/.."

# Needs a JDK 21+; the emulator will not start on older Java.
. tool/lib/require_jdk21.sh

[ -d test/rules/node_modules ] || npm --prefix test/rules install --silent

exec firebase emulators:exec --only firestore,storage --project demo-impairgency \
  "npm --prefix test/rules test"
