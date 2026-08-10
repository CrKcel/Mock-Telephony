#!/usr/bin/env bash
set -euo pipefail

# Build the module-owned daemon (daemon/ + radio-aidl/): verify the frozen AIDL
# hashes, compile the compile-only android.os declarations, generate the stable
# AIDL Java, compile every daemon source, and dex it into
# out/artifacts/mockmodem.jar. The module is self-hosted: there is no separate
# shared runtime — the daemon tree is a first-class part of this repository.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-env.sh
. "$SCRIPT_DIR/lib/build-env.sh"

resolve_android_tools
load_aidl_version

java_major=$(javac -version 2>&1 | sed -E 's/.* ([0-9]+).*/\1/')
[ "$java_major" -ge 11 ] || die "JDK 11 or newer is required"
aidl_sdk=$("$AIDL_BIN" --help 2>&1 \
  | sed -n 's/.*built for platform SDK version \([0-9][0-9]*\).*/\1/p' | head -n 1 || true)
[ -n "$aidl_sdk" ] && [ "$aidl_sdk" -ge 34 ] \
  || die "AIDL compiler from Android build-tools 34 or newer is required"

API_ROOT="$PROJECT_ROOT/radio-aidl/api/$AIDL_VERSION"
DAEMON_SRC="$PROJECT_ROOT/daemon/src/main/java"
STUB_SRC="$PROJECT_ROOT/daemon/compile-only-stubs"
BUILD_DIR="$PROJECT_ROOT/out/build"
GEN_DIR="$BUILD_DIR/generated"
STUB_CLASSES="$BUILD_DIR/compile-only-classes"
MAIN_CLASSES="$BUILD_DIR/classes"
STUB_JAR="$BUILD_DIR/compile-only-stubs.jar"
DEX_DIR="$BUILD_DIR/dex"
ARTIFACT_DIR="$PROJECT_ROOT/out/artifacts"
MODULE_JAR="$ARTIFACT_DIR/mockmodem.jar"
JAR_DATE="${JAR_DATE:-2024-01-01T00:00:00Z}"

verify_hash() {
  local package_name="$1" expected="$2" actual
  actual=$(aidl_dump_hash "$package_name")
  [ "$actual" = "$expected" ] \
    || die "AIDL v$AIDL_VERSION $package_name API drift: expected $expected, got $actual"
  [ "$actual" != 0000000000000000000000000000000000000000 ] \
    || die "zero AIDL hash is forbidden"
}

generate_aidl() {
  local package_name="$1" interface_hash="$2"
  shift 2
  echo "  AIDL $package_name hash=$interface_hash"
  "$AIDL_BIN" --lang=java --structured --stability=vintf \
    --version="$AIDL_VERSION" --hash="$interface_hash" \
    -I"$API_ROOT" -o"$GEN_DIR" "$@"
}

echo "[daemon 1/6] verify toolchain and frozen AIDL v$AIDL_VERSION"
echo "  aidl: $AIDL_BIN"
echo "  platform: $ANDROID_PLATFORM_JAR"
echo "  javac: $(javac -version 2>&1)"
echo "  out: $BUILD_DIR"
verify_hash common "$AIDL_HASH_COMMON"
for package_name in config data messaging modem network sim voice; do
  hash_var="AIDL_HASH_${package_name^^}"
  verify_hash "$package_name" "${!hash_var}"
done

echo "[daemon 2/6] prepare build directories"
rm -rf "$BUILD_DIR"
mkdir -p "$GEN_DIR" "$STUB_CLASSES" "$MAIN_CLASSES" "$ARTIFACT_DIR"

echo "[daemon 3/6] compile hidden API declarations as compile-only classpath"
mapfile -d '' stub_sources < <(find "$STUB_SRC" -name '*.java' -print0 | sort -z)
javac -source 11 -target 11 -Xlint:-options \
  -classpath "$ANDROID_PLATFORM_JAR" -d "$STUB_CLASSES" "${stub_sources[@]}"
jar --create --file "$STUB_JAR" --date="$JAR_DATE" -C "$STUB_CLASSES" .

echo "[daemon 4/6] generate stable AIDL Java without rewriting generated sources"
mapfile -d '' common_aidl < <(
  find "$API_ROOT/android/hardware/radio" -maxdepth 1 -name '*.aidl' -print0 | sort -z
)
generate_aidl common "$AIDL_HASH_COMMON" "${common_aidl[@]}"
for package_name in config data messaging modem network sim voice; do
  hash_var="AIDL_HASH_${package_name^^}"
  mapfile -d '' package_aidl < <(
    find "$API_ROOT/android/hardware/radio/$package_name" -name '*.aidl' -print0 | sort -z
  )
  generate_aidl "$package_name" "${!hash_var}" "${package_aidl[@]}"
done

echo "[daemon 5/6] compile module daemon sources (generated AIDL + daemon/)"
mapfile -d '' daemon_sources < <(
  find "$GEN_DIR" "$DAEMON_SRC" -name '*.java' -print0 | sort -z
)
javac -source 11 -target 11 -Xlint:-options \
  -classpath "$STUB_JAR:$ANDROID_PLATFORM_JAR" \
  -d "$MAIN_CLASSES" "${daemon_sources[@]}"

echo "[daemon 6/6] create dex with compile-only stubs excluded and package jar"
rm -rf "$DEX_DIR"
mkdir -p "$DEX_DIR"

mapfile -d '' class_files < <(
  find "$MAIN_CLASSES" -name '*.class' -print0 | sort -z
)
"$D8_BIN" --release --lib "$ANDROID_PLATFORM_JAR" --min-api 30 \
  --output "$DEX_DIR" "${class_files[@]}"

if "$DEXDUMP_BIN" -d "$DEX_DIR/classes.dex" 2>/dev/null \
    | grep -Eq "Class descriptor.*Landroid/os/(AsyncResult|Binder|Parcelable|RegistrantList|ServiceManager);"; then
  die "compile-only android.os class leaked into classes.dex"
fi

jar --create --file "$MODULE_JAR" --date="$JAR_DATE" -C "$DEX_DIR" classes.dex
