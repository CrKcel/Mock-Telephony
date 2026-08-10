#!/usr/bin/env bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

resolve_android_tools() {
  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  local candidate

  AIDL_BIN="${AIDL_BIN:-}"
  if [ -z "$AIDL_BIN" ] && command -v aidl >/dev/null 2>&1; then
    AIDL_BIN="$(command -v aidl)"
  fi
  if [ -z "$AIDL_BIN" ] && [ -n "$sdk_root" ]; then
    candidate=$(find "$sdk_root/build-tools" -mindepth 2 -maxdepth 2 -type f -name aidl \
      2>/dev/null | sort -V | tail -n 1)
    AIDL_BIN="$candidate"
  fi

  D8_BIN="${D8_BIN:-}"
  if [ -z "$D8_BIN" ] && command -v d8 >/dev/null 2>&1; then
    D8_BIN="$(command -v d8)"
  fi
  if [ -z "$D8_BIN" ] && [ -n "$sdk_root" ]; then
    candidate=$(find "$sdk_root/build-tools" -mindepth 2 -maxdepth 2 -type f -name d8 \
      2>/dev/null | sort -V | tail -n 1)
    D8_BIN="$candidate"
  fi

  DEXDUMP_BIN="${DEXDUMP_BIN:-}"
  if [ -z "$DEXDUMP_BIN" ] && command -v dexdump >/dev/null 2>&1; then
    DEXDUMP_BIN="$(command -v dexdump)"
  fi
  if [ -z "$DEXDUMP_BIN" ] && [ -n "$sdk_root" ]; then
    candidate=$(find "$sdk_root/build-tools" -mindepth 2 -maxdepth 2 -type f -name dexdump \
      2>/dev/null | sort -V | tail -n 1)
    DEXDUMP_BIN="$candidate"
  fi

  ANDROID_PLATFORM_JAR="${ANDROID_PLATFORM_JAR:-}"
  if [ -z "$ANDROID_PLATFORM_JAR" ] && [ -n "$sdk_root" ]; then
    candidate=$(find "$sdk_root/platforms" -mindepth 2 -maxdepth 2 -type f -name android.jar \
      2>/dev/null | sort -V | tail -n 1)
    ANDROID_PLATFORM_JAR="$candidate"
  fi

  [ -x "$AIDL_BIN" ] || die "set AIDL_BIN or ANDROID_SDK_ROOT to an SDK with aidl"
  [ -x "$D8_BIN" ] || die "set D8_BIN or ANDROID_SDK_ROOT to an SDK with d8"
  [ -x "$DEXDUMP_BIN" ] || die "set DEXDUMP_BIN or ANDROID_SDK_ROOT to an SDK with dexdump"
  [ -f "$ANDROID_PLATFORM_JAR" ] \
    || die "set ANDROID_PLATFORM_JAR or install an Android SDK platform"

  require_command javac
  require_command jar
  require_command sha1sum
}

aidl_dump_hash() {
  local package_dir="$1" api_root temp_root hash
  api_root="$PROJECT_ROOT/radio-aidl/api/1"
  temp_root=$(mktemp -d)
  mkdir -p "$temp_root/android/hardware/radio"
  if [ "$package_dir" = common ]; then
    find "$api_root/android/hardware/radio" -maxdepth 1 -type f -name '*.aidl' \
      -exec cp {} "$temp_root/android/hardware/radio/" \;
  else
    cp -a "$api_root/android/hardware/radio/$package_dir" \
      "$temp_root/android/hardware/radio/"
  fi
  hash=$(
    cd "$temp_root"
    {
      find ./ -name '*.aidl' -print0 | LC_ALL=C sort -z | xargs -0 sha1sum
      echo latest-version
    } | sha1sum | cut -d ' ' -f 1
  )
  find "$temp_root" -depth -delete
  echo "$hash"
}

load_aidl_version() {
  . "$PROJECT_ROOT/radio-aidl/version.properties"
}

module_property() {
  local key="$1"
  sed -n "s/^${key}=//p" "$PROJECT_ROOT/module/module.prop" | head -n 1
}
