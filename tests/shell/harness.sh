#!/usr/bin/env bash
#
# Behavioral test harness for the module shell scripts.
#
# Runs a module script inside a bwrap sandbox that provides:
#   - a fake /system and /data tree (writable), with the real module/ copied
#     into /data/adb/modules/mock_telephony (MODDIR)
#   - a fake /proc/filesystems advertising overlayfs
#   - shimmed commands (mount/umount/mountpoint/getprop/resetprop/pm/su/
#     app_process/sleep/chcon) that record invocations into $SANDBOX/trace
#     and are driven by $SANDBOX/etc config files
#   - the host's real toolchain read-only (/usr /bin /lib /etc)
#
# No module source file is modified: the sandbox only mirrors the environment
# the scripts expect. Requires bwrap with unprivileged user namespaces.

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"
MODULE_SRC="$REPO_ROOT/module"

TEST_PASS=0
TEST_FAIL=0
SANDBOX=""

# ----- assert helpers (return 1 on mismatch; call with `|| return 1`) -----

assert_eq() {
  [ "$1" = "$2" ] || { echo "  ASSERT: expected [$2], got [$1]" >&2; return 1; }
}
assert_file_contains() {
  grep -qF -- "$2" "$1" 2>/dev/null \
    || { echo "  ASSERT: $1 lacks [$2]" >&2; return 1; }
}
assert_file_not_contains() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then
    echo "  ASSERT: $1 unexpectedly contains [$2]" >&2
    return 1
  fi
}
assert_exists() {
  [ -e "$1" ] || { echo "  ASSERT: $1 missing" >&2; return 1; }
}
assert_not_exists() {
  [ ! -e "$1" ] || { echo "  ASSERT: $1 unexpectedly exists" >&2; return 1; }
}
assert_log_contains() {
  local log="$SANDBOX/data/adb/modules/mock_telephony/.runtime/mock_telephony.log"
  assert_file_contains "$log" "$1"
}

# ----- sandbox control -----

# Sanity gate: bwrap + user namespaces must work.
harness_check_bwrap() {
  if ! command -v bwrap >/dev/null 2>&1; then
    echo "harness: bwrap is required (package bubblewrap)" >&2
    exit 2
  fi
  if ! bwrap --unshare-user --ro-bind /usr /usr --ro-bind /bin /bin \
      --ro-bind /lib /lib --ro-bind /lib64 /lib64 -- /bin/sh -c 'exit 0' \
      >/dev/null 2>&1; then
    echo "harness: bwrap with unprivileged user namespaces is required" >&2
    exit 2
  fi
}

harness_init() {
  SANDBOX="$(mktemp -d)"

  # system tree
  mkdir -p "$SANDBOX/system/etc/permissions" "$SANDBOX/system/etc/vintf/manifest"
  mkdir -p "$SANDBOX/system/bin"
  ln -s /bin/sh "$SANDBOX/system/bin/sh"

  # data/adb tree + module dir (the real module source becomes MODDIR)
  mkdir -p "$SANDBOX/data/adb/ksu/bin" "$SANDBOX/data/adb/magisk" \
    "$SANDBOX/data/adb/ap/bin" "$SANDBOX/data/adb/modules"
  cp -a "$MODULE_SRC" "$SANDBOX/data/adb/modules/mock_telephony"

  # config + trace + fake bin dirs
  mkdir -p "$SANDBOX/etc" "$SANDBOX/trace" "$SANDBOX/bin"
  : > "$SANDBOX/etc/getprop.conf"
  : > "$SANDBOX/etc/resetprop_fail.conf"
  : > "$SANDBOX/etc/pm_features.conf"
  : > "$SANDBOX/etc/service_list.conf"
  : > "$SANDBOX/etc/dumpsys.conf"
  : > "$SANDBOX/etc/mounted_paths"
  : > "$SANDBOX/etc/app_process_behavior"
  echo 0 > "$SANDBOX/etc/mount_result"
  printf 'nodev overlay\n\ttmpfs\n' > "$SANDBOX/etc/filesystems"

  write_shims
}

harness_cleanup() {
  [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
  SANDBOX=""
}

# ----- config setters (used by test cases before harness_run) -----

set_prop() { echo "$1=$2" >> "$SANDBOX/etc/getprop.conf"; }
set_mount_result() { echo "$1" > "$SANDBOX/etc/mount_result"; }
set_mounted() { echo "$1" >> "$SANDBOX/etc/mounted_paths"; }
set_pm_features() { printf '%s\n' "$@" >> "$SANDBOX/etc/pm_features.conf"; }
set_service_list() { printf '%s\n' "$@" >> "$SANDBOX/etc/service_list.conf"; }
set_dumpsys() { printf '%s\n' "$@" >> "$SANDBOX/etc/dumpsys.conf"; }
set_app_process_behavior() { echo "$1" > "$SANDBOX/etc/app_process_behavior"; }
remove_resetprop() {
  rm -f "$SANDBOX/data/adb/ksu/bin/resetprop" \
    "$SANDBOX/data/adb/magisk/resetprop" \
    "$SANDBOX/data/adb/ap/bin/resetprop"
}
remove_ksu_resetprop() { rm -f "$SANDBOX/data/adb/ksu/bin/resetprop"; }
remove_magisk_resetprop() { rm -f "$SANDBOX/data/adb/magisk/resetprop"; }
remove_apatch_resetprop() { rm -f "$SANDBOX/data/adb/ap/bin/resetprop"; }
remove_module_prop() { rm -f "$SANDBOX/data/adb/modules/mock_telephony/module.prop"; }

# seed a file inside the module .runtime dir (markers, originals, pidfiles)
seed_runtime() {
  local name="$1" content="$2"
  local rt="$SANDBOX/data/adb/modules/mock_telephony/.runtime"
  mkdir -p "$rt"
  printf '%s' "$content" > "$rt/$name"
}

# ----- run commands in the sandbox; returns the command's exit code -----

sandbox_exec() {
  bwrap \
    --unshare-user \
    --dev /dev --tmpfs /tmp \
    --ro-bind /proc /proc \
    --ro-bind "$SANDBOX/etc/filesystems" /proc/filesystems \
    --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /sbin /sbin \
    --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind /etc /etc \
    --bind "$SANDBOX/system" /system \
    --bind "$SANDBOX/data" /data \
    --bind "$SANDBOX/bin" /sandbox-bin \
    --bind "$SANDBOX/etc" /sandbox-etc \
    --bind "$SANDBOX/trace" /sandbox-trace \
    --setenv PATH "/sandbox-bin:/usr/bin:/bin" \
    "$@"
}

# run a module script; returns its exit code
harness_run() {
  local rel="$1"
  shift
  sandbox_exec /bin/sh "/data/adb/modules/mock_telephony/$rel" "$@"
}

# run an arbitrary shell command in the sandbox (for composing scenarios)
harness_sh() {
  sandbox_exec /bin/sh "$@"
}

# ----- test case runner -----

run_case() {
  local name="$1" fn="$2"
  harness_init
  local rc=0
  if ! "$fn"; then rc=1; fi
  harness_cleanup
  if [ "$rc" -eq 0 ]; then
    TEST_PASS=$((TEST_PASS + 1))
    echo "  ok   $name"
  else
    TEST_FAIL=$((TEST_FAIL + 1))
    echo "  FAIL $name" >&2
  fi
}

summary() {
  echo "shell tests: $TEST_PASS passed, $TEST_FAIL failed"
  [ "$TEST_FAIL" -eq 0 ]
}

trap 'harness_cleanup' EXIT

# ----- sandbox command shims (written into the sandbox) -----

write_shims() {
  local sb="$SANDBOX"

  cat > "$sb/bin/getprop" <<'SHIM'
#!/bin/sh
key="$1"
printf 'getprop %s\n' "$key" >> /sandbox-trace/getprop
[ -z "$key" ] && exit 0
grep -F "${key}=" /sandbox-etc/getprop.conf 2>/dev/null | head -n1 | cut -d= -f2-
exit 0
SHIM

  cat > "$sb/bin/resetprop" <<'SHIM'
#!/bin/sh
if [ "$1" = "-n" ] && [ -n "${2:-}" ]; then
  key="$2"; value="${3:-}"
  printf 'resetprop %s %s\n' "$key" "$value" >> /sandbox-trace/resetprop
  if grep -Fq "$key" /sandbox-etc/resetprop_fail.conf 2>/dev/null; then
    exit 1
  fi
  sed -i "/^${key}=/d" /sandbox-etc/getprop.conf 2>/dev/null || true
  printf '%s=%s\n' "$key" "$value" >> /sandbox-etc/getprop.conf
  exit 0
fi
printf 'resetprop %s\n' "$*" >> /sandbox-trace/resetprop
exit 0
SHIM

  cat > "$sb/bin/mount" <<'SHIM'
#!/bin/sh
printf 'mount %s\n' "$*" >> /sandbox-trace/mount
# last arg is the overlay target
target=""
for a in "$@"; do target="$a"; done
if [ "$(cat /sandbox-etc/mount_result 2>/dev/null)" = "0" ]; then
  [ -n "$target" ] && printf '%s\n' "$target" >> /sandbox-etc/mounted_paths
  exit 0
fi
exit 1
SHIM

  cat > "$sb/bin/umount" <<'SHIM'
#!/bin/sh
printf 'umount %s\n' "$*" >> /sandbox-trace/umount
for p in "$@"; do sed -i "\|^${p}$|d" /sandbox-etc/mounted_paths 2>/dev/null || true; done
exit 0
SHIM

  cat > "$sb/bin/mountpoint" <<'SHIM'
#!/bin/sh
[ "$1" = "-q" ] || exit 2
target="$2"
printf 'mountpoint %s\n' "$target" >> /sandbox-trace/mountpoint
grep -Fxq "$target" /sandbox-etc/mounted_paths 2>/dev/null && exit 0
exit 1
SHIM

  cat > "$sb/bin/chcon" <<'SHIM'
#!/bin/sh
printf 'chcon %s\n' "$*" >> /sandbox-trace/chcon
exit 0
SHIM

  cat > "$sb/bin/pm" <<'SHIM'
#!/bin/sh
printf 'pm %s\n' "$*" >> /sandbox-trace/pm
if [ "$1" = "list" ] && [ "${2:-}" = "features" ]; then
  cat /sandbox-etc/pm_features.conf
  exit 0
fi
exit 1
SHIM

  cat > "$sb/bin/su" <<'SHIM'
#!/bin/sh
printf 'su %s\n' "$*" >> /sandbox-trace/su
exit 0
SHIM

  # Instant sleep so watchdog/supervisor loops iterate fast in tests. The
  # requested interval is recorded so backoff behavior can be asserted.
  cat > "$sb/bin/sleep" <<'SHIM'
#!/bin/sh
printf 'sleep %s\n' "$*" >> /sandbox-trace/sleep
exit 0
SHIM

  # Boot diagnostics: boot-completed.sh inspects services and dumpsys.
  cat > "$sb/bin/service" <<'SHIM'
#!/bin/sh
printf 'service %s\n' "$*" >> /sandbox-trace/service
if [ "$1" = "check" ]; then
  echo "Service ${2:-}: found"
  exit 0
fi
if [ "$1" = "list" ]; then
  cat /sandbox-etc/service_list.conf
  exit 0
fi
exit 0
SHIM

  cat > "$sb/bin/dumpsys" <<'SHIM'
#!/bin/sh
printf 'dumpsys %s\n' "$*" >> /sandbox-trace/dumpsys
cat /sandbox-etc/dumpsys.conf
exit 0
SHIM

  # Framework-specific full paths used by bootstrap/uninstall. Each wrapper
  # records which manager implementation was selected before delegating to the
  # shared behavior shim.
  cat > "$sb/data/adb/ksu/bin/resetprop" <<'SHIM'
#!/bin/sh
echo ksu >> /sandbox-trace/resetprop-framework
exec /sandbox-bin/resetprop "$@"
SHIM

  cat > "$sb/data/adb/magisk/resetprop" <<'SHIM'
#!/bin/sh
echo magisk >> /sandbox-trace/resetprop-framework
exec /sandbox-bin/resetprop "$@"
SHIM

  cat > "$sb/data/adb/ap/bin/resetprop" <<'SHIM'
#!/bin/sh
echo apatch >> /sandbox-trace/resetprop-framework
exec /sandbox-bin/resetprop "$@"
SHIM

  cat > "$sb/system/bin/su" <<'SHIM'
#!/bin/sh
echo system >> /sandbox-trace/su-framework
exec /sandbox-bin/su "$@"
SHIM

  cat > "$sb/data/adb/magisk/su" <<'SHIM'
#!/bin/sh
echo magisk >> /sandbox-trace/su-framework
exec /sandbox-bin/su "$@"
SHIM

  cat > "$sb/data/adb/ap/bin/su" <<'SHIM'
#!/bin/sh
echo apatch >> /sandbox-trace/su-framework
exec /sandbox-bin/su "$@"
SHIM

  # Full-path app_process used by the supervisor. Behavior driven by config:
  #   empty/exit -> log and exit 0 (daemon crashes immediately)
  #   stay       -> stay alive so the supervisor can adopt it
  cat > "$sb/system/bin/app_process" <<'SHIM'
#!/bin/sh
printf 'app_process %s\n' "$*" >> /sandbox-trace/app_process
behavior=$(cat /sandbox-etc/app_process_behavior 2>/dev/null)
if [ "$behavior" = "stay" ]; then
  /bin/sleep 30
fi
exit 0
SHIM

  chmod +x "$sb/bin"/* "$sb/system/bin/app_process" "$sb/system/bin/su" \
    "$sb/data/adb/ksu/bin/resetprop" "$sb/data/adb/magisk/resetprop" \
    "$sb/data/adb/magisk/su" "$sb/data/adb/ap/bin/resetprop" \
    "$sb/data/adb/ap/bin/su"
}
