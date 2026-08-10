#!/usr/bin/env bash
set -euo pipefail

# Compile and run the JVM unit tests for the module daemon. Requires the
# daemon to be built first (tools/build.sh) so out/build/classes and
# out/build/compile-only-classes exist; runs inside tools/check.sh.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-env.sh
. "$SCRIPT_DIR/../tools/lib/build-env.sh"
resolve_android_tools

MAIN_CLASSES="$PROJECT_ROOT/out/build/classes"
TEST_CLASSES="$PROJECT_ROOT/out/test-classes"
TEST_SRC="$SCRIPT_DIR/java/src"
TEST_STUB_SRC="$SCRIPT_DIR/java/stub"

[ -d "$MAIN_CLASSES" ] || die "daemon classes missing; run tools/build.sh first"

rm -rf "$TEST_CLASSES"
mkdir -p "$TEST_CLASSES"
mapfile -d '' test_sources < <(
  find "$TEST_SRC" "$TEST_STUB_SRC" -name '*.java' -print0 | sort -z
)
javac -source 11 -target 11 -Xlint:-options \
  -classpath "$MAIN_CLASSES:$ANDROID_PLATFORM_JAR" \
  -d "$TEST_CLASSES" "${test_sources[@]}"

# android.jar is a compile-time stub (methods carry no Code attribute), so it
# must NOT be on the runtime classpath. The stub android.util.Log and
# android.os.Parcelable compiled into TEST_CLASSES stand in for the platform;
# -Xverify:none avoids resolving the Parcel parameter type that is only
# referenced by the never-invoked marshalling methods.
for main in MockNetworkServiceTest MockSimServiceTest; do
  echo "  java tests: $main"
  java -Xverify:none -cp "$TEST_CLASSES:$MAIN_CLASSES" \
    "android.telephony.mockmodem.$main"
done
