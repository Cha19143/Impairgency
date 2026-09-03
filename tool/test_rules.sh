#!/usr/bin/env bash
# Runs the Firestore and Storage security rules suites against the local emulator.
#
#   tool/test_rules.sh
#
# No Firebase project or network needed - the emulator runs against a demo
# project id. Requires a JDK 21+; the emulator will not start on older Java.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! java -version 2>&1 | grep -qE '"(2[1-9]|[3-9][0-9])'; then
  for candidate in \
    /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
    /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home \
    /usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home; do
    if [ -x "$candidate/bin/java" ]; then
      export JAVA_HOME="$candidate"
      export PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi

if ! java -version 2>&1 | grep -qE '"(2[1-9]|[3-9][0-9])'; then
  echo "The Firestore emulator needs a JDK 21 or newer." >&2
  echo "Found: $(java -version 2>&1 | head -1)" >&2
  echo "Install one with:  brew install openjdk@21" >&2
  exit 1
fi

[ -d test/rules/node_modules ] || npm --prefix test/rules install --silent

exec firebase emulators:exec --only firestore,storage --project demo-impairgency \
  "npm --prefix test/rules test"
