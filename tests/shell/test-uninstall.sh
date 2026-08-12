#!/usr/bin/env bash
# Behavioral tests for module/uninstall.sh: property restore and .runtime
# teardown.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

RT() { echo "$SANDBOX/data/adb/modules/mock_telephony/.runtime"; }

case_restores_properties() {
  seed_runtime radio.noril.original "true"
  harness_run uninstall.sh; local rc=$?
  [ "$rc" -eq 0 ] || { echo "  ASSERT: uninstall rc=$rc" >&2; return 1; }
  assert_file_contains "$SANDBOX/trace/resetprop" \
    "ro.radio.noril true" || return 1
  # .runtime (marker, originals, log) is removed wholesale.
  assert_not_exists "$(RT)" || return 1
  return 0
}

case_resetprop_missing_skips_restore() {
  remove_resetprop
  harness_run uninstall.sh; local rc=$?
  [ "$rc" -eq 0 ] || { echo "  ASSERT: uninstall rc=$rc" >&2; return 1; }
  assert_not_exists "$SANDBOX/trace/resetprop" || return 1
  assert_not_exists "$(RT)" || return 1
  return 0
}

case_unmounts_bind_mirror() {
  # A bind-mirror tmpfs under .runtime must be unmounted before teardown so the
  # .runtime tree can be removed. Seed the *sandbox-internal* path: mounted_paths
  # is read inside the sandbox, where /data/adb/... is the module root.
  local rt
  rt="$(RT)"
  local internal="/data/adb/modules/mock_telephony/.runtime/bind-system-etc-permissions"
  mkdir -p "$rt/bind-system-etc-permissions"
  set_mounted "$internal"
  harness_run uninstall.sh || return 1
  assert_file_contains "$SANDBOX/trace/umount" "$internal" || return 1
  return 0
}

run_case uninstall:restores-properties case_restores_properties
run_case uninstall:resetprop-missing-skips-restore case_resetprop_missing_skips_restore
run_case uninstall:unmounts-bind-mirror case_unmounts_bind_mirror

summary
