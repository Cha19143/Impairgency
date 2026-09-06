# Puts a JDK 21+ on PATH, or explains why the emulator will not start.
#
# Sourced, not run:  . tool/lib/require_jdk21.sh
#
# The Firestore emulator will not start on older Java, and macOS still ships
# with 1.8 on plenty of machines. Shared by tool/test_rules.sh and
# tool/test_e2e.sh so the two cannot drift apart.

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
