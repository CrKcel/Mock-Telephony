#!/usr/bin/env bash
# Behavioral tests for module/post-fs-data.sh: overlay injection, property
# bootstrap, and the failure rollback path.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

RT() { echo "$SANDBOX/data/adb/modules/mock_telephony/.runtime"; }

case_overlay_success() {
  harness_run post-fs-data.sh || return 1
  local rt
  rt="$(RT)"
  # Both overlays mounted, feature + VINTF injected.
  local mount_count
  mount_count=$(grep -c -- '-t overlay' "$SANDBOX/trace/mount")
  [ "$mount_count" -eq 2 ] || { echo "  ASSERT: expected 2 overlay mounts, got $mount_count" >&2; return 1; }
  assert_file_contains "$SANDBOX/trace/mount" "/system/etc/permissions" || return 1
  assert_file_contains "$SANDBOX/trace/mount" "/system/etc/vintf/manifest" || return 1
  assert_exists "$SANDBOX/system/etc/permissions/mock-telephony-features.xml" || return 1
  assert_exists "$SANDBOX/system/etc/vintf/manifest/mockmodem.radio.xml" || return 1
  # Properties set only after both overlays are usable; originals captured first.
  assert_file_contains "$SANDBOX/trace/resetprop" "ro.radio.noril false" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "persist.radio.allow_mock_modem true" || return 1
  assert_file_contains "$rt/radio.noril.original" "true" || return 1
  # No failure marker.
  assert_not_exists "$rt/.bootstrap_failed" || return 1
  assert_log_contains "[post-fs-data] done" || return 1
  return 0
}

case_overlay_failure_rolls_back() {
  set_mount_result 1
  harness_run post-fs-data.sh; local rc=$?
  [ "$rc" -ne 0 ] || { echo "  ASSERT: expected failure exit" >&2; return 1; }
  local rt
  rt="$(RT)"
  assert_exists "$rt/.bootstrap_failed" || return 1
  # Failure path restores the captured originals (device had no explicit value).
  assert_file_contains "$SANDBOX/trace/resetprop" "ro.radio.noril true" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "persist.radio.allow_mock_modem false" || return 1
  assert_log_contains "bootstrap prerequisites failed" || return 1
  return 0
}

case_resetprop_missing_blocks() {
  remove_resetprop
  harness_run post-fs-data.sh; local rc=$?
  [ "$rc" -ne 0 ] || { echo "  ASSERT: expected failure exit" >&2; return 1; }
  local rt
  rt="$(RT)"
  assert_exists "$rt/.bootstrap_failed" || return 1
  # Overlays succeeded but no property was set: nothing written, loud error.
  assert_not_exists "$SANDBOX/trace/resetprop" || return 1
  assert_log_contains "resetprop missing" || return 1
  return 0
}

case_foreign_mount_refused() {
  # Another owner already mounted the permissions dir: module must refuse.
  set_mounted /system/etc/permissions
  harness_run post-fs-data.sh; local rc=$?
  [ "$rc" -ne 0 ] || { echo "  ASSERT: expected failure exit" >&2; return 1; }
  local rt
  rt="$(RT)"
  assert_exists "$rt/.bootstrap_failed" || return 1
  assert_log_contains "overlay conflict, refusing foreign mount" || return 1
  # The VINTF overlay mounted this run is unmounted on the way out.
  assert_file_contains "$SANDBOX/trace/umount" "/system/etc/vintf/manifest" || return 1
  return 0
}

case_resetprop_fail_blocks() {
  # Overlays succeed but the first property write (ro.radio.noril) fails:
  # the module must restore what it changed and block services.
  echo "ro.radio.noril" > "$SANDBOX/etc/resetprop_fail.conf"
  harness_run post-fs-data.sh; local rc=$?
  [ "$rc" -ne 0 ] || { echo "  ASSERT: expected failure exit" >&2; return 1; }
  local rt
  rt="$(RT)"
  assert_exists "$rt/.bootstrap_failed" || return 1
  assert_log_contains "failed to set ro.radio.noril" || return 1
  # Rollback reset allow_mock_modem to the default.
  assert_file_contains "$SANDBOX/trace/resetprop" \
    "persist.radio.allow_mock_modem false" || return 1
  return 0
}

case_bind_fallback() {
  # Kernel without overlayfs: injection uses the tmpfs mirror + bind backend and
  # the bootstrap properties are still applied.
  printf 'nodev tmpfs\n' > "$SANDBOX/etc/filesystems"
  harness_run post-fs-data.sh || return 1
  local rt
  rt="$(RT)"
  assert_file_contains "$SANDBOX/trace/mount" "-t tmpfs" || return 1
  assert_file_contains "$SANDBOX/trace/mount" "--bind" || return 1
  assert_exists "$rt/bind-system-etc-permissions/mock-telephony-features.xml" || return 1
  assert_exists "$rt/bind-system-etc-vintf-manifest/mockmodem.radio.xml" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "ro.radio.noril false" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "persist.radio.allow_mock_modem true" || return 1
  assert_not_exists "$rt/.bootstrap_failed" || return 1
  return 0
}

case_bind_failure_rolls_back() {
  # No overlayfs and the bind backend cannot mount either: block services and
  # restore the captured originals, exactly like an overlay failure.
  printf 'nodev tmpfs\n' > "$SANDBOX/etc/filesystems"
  set_mount_result 1
  harness_run post-fs-data.sh; local rc=$?
  [ "$rc" -ne 0 ] || { echo "  ASSERT: expected failure exit" >&2; return 1; }
  local rt
  rt="$(RT)"
  assert_exists "$rt/.bootstrap_failed" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "ro.radio.noril true" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "persist.radio.allow_mock_modem false" || return 1
  return 0
}

case_original_property_preserved() {
  set_prop ro.radio.noril true
  seed_runtime radio.noril.original "false"
  harness_run post-fs-data.sh || return 1
  local rt
  rt="$(RT)"
  # save_original_properties must not overwrite an already-captured original.
  assert_file_contains "$rt/radio.noril.original" "false" || return 1
  if grep -q '^true$' "$rt/radio.noril.original"; then
    echo "  ASSERT: radio.noril.original was overwritten" >&2
    return 1
  fi
  return 0
}

case_apatch_defers_until_post_mount() {
  local rc=0
  harness_sh -c 'APATCH=true /data/adb/modules/mock_telephony/post-fs-data.sh' || rc=$?
  [ "$rc" -eq 0 ] || { echo "  ASSERT: APatch post-fs-data rc=$rc" >&2; return 1; }
  assert_not_exists "$SANDBOX/trace/resetprop" || return 1
  : > "$SANDBOX/system/etc/permissions/mock-telephony-features.xml"
  : > "$SANDBOX/system/etc/vintf/manifest/mockmodem.radio.xml"
  harness_sh -c 'APATCH=true /data/adb/modules/mock_telephony/post-mount.sh' || return 1
  assert_not_exists "$SANDBOX/trace/mount" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "ro.radio.noril false" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "persist.radio.allow_mock_modem true" || return 1
  return 0
}

case_apatch_post_mount_bind_fallback() {
  printf 'nodev tmpfs\n' > "$SANDBOX/etc/filesystems"
  harness_sh -c 'APATCH=true /data/adb/modules/mock_telephony/post-fs-data.sh' || return 1
  harness_sh -c 'APATCH=true /data/adb/modules/mock_telephony/post-mount.sh' || return 1
  assert_file_contains "$SANDBOX/trace/mount" "-t tmpfs" || return 1
  assert_file_contains "$SANDBOX/trace/mount" "--bind" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "ro.radio.noril false" || return 1
  return 0
}

run_case post-fs-data:overlay-success case_overlay_success
run_case post-fs-data:overlay-failure-rollback case_overlay_failure_rolls_back
run_case post-fs-data:resetprop-missing-block case_resetprop_missing_blocks
run_case post-fs-data:resetprop-fail-blocks case_resetprop_fail_blocks
run_case post-fs-data:foreign-mount-refused case_foreign_mount_refused
run_case post-fs-data:bind-fallback case_bind_fallback
run_case post-fs-data:bind-failure-rolls-back case_bind_failure_rolls_back
run_case post-fs-data:original-property-preserved case_original_property_preserved
run_case post-fs-data:apatch-defers-until-post-mount case_apatch_defers_until_post_mount
run_case post-fs-data:apatch-post-mount-bind-fallback case_apatch_post_mount_bind_fallback

summary
