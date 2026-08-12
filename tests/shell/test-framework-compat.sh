#!/usr/bin/env bash
# Offline compatibility matrix for Magisk and APatch module environments.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

RT() { echo "$SANDBOX/data/adb/modules/mock_telephony/.runtime"; }

case_magisk_resetprop_preferred() {
  local resolved
  resolved=$(harness_sh -c '
    MODDIR=/data/adb/modules/mock_telephony
    MAGISKTMP=/data/adb/magisk
    export MODDIR MAGISKTMP
    . "$MODDIR/common.sh"
    find_resetprop
  ') || return 1
  assert_eq "$resolved" /data/adb/magisk/resetprop
}

case_apatch_resetprop_preferred() {
  local resolved
  resolved=$(harness_sh -c '
    MODDIR=/data/adb/modules/mock_telephony
    MAGISKTMP=/data/adb/magisk
    APATCH=true
    export MODDIR MAGISKTMP APATCH
    . "$MODDIR/common.sh"
    find_resetprop
  ') || return 1
  assert_eq "$resolved" /data/adb/ap/bin/resetprop
}

case_magisk_customize_keeps_manual_mount() {
  set_prop ro.build.version.sdk 36
  harness_sh -c '
    MODPATH=/data/adb/modules/mock_telephony
    MAGISKTMP=/data/adb/magisk
    export MODPATH MAGISKTMP
    "$MODPATH/customize.sh"
  ' || return 1
  assert_exists "$SANDBOX/data/adb/modules/mock_telephony/skip_mount" || return 1
  assert_file_contains "$SANDBOX/data/adb/modules/mock_telephony/sepolicy.rule" \
    "allow magisk hal_radio_service" || return 1
  assert_file_not_contains "$SANDBOX/data/adb/modules/mock_telephony/sepolicy.rule" \
    "allow ksu " || return 1
}

case_apatch_wins_compat_environment() {
  set_prop ro.build.version.sdk 36
  local out
  out=$(harness_sh -c '
    MODPATH=/data/adb/modules/mock_telephony
    MAGISKTMP=/data/adb/magisk
    APATCH=true
    export MODPATH MAGISKTMP APATCH
    "$MODPATH/customize.sh"
  ') || return 1
  assert_not_exists "$SANDBOX/data/adb/modules/mock_telephony/skip_mount" || return 1
  printf '%s\n' "$out" | grep -Fq "root framework: apatch" \
    || { echo "  ASSERT: APatch did not win framework detection" >&2; return 1; }
}

case_magisk_overlay_lifecycle() {
  harness_sh -c '
    MAGISKTMP=/data/adb/magisk
    export MAGISKTMP
    /data/adb/modules/mock_telephony/post-fs-data.sh
  ' || return 1
  assert_file_contains "$SANDBOX/trace/resetprop-framework" magisk || return 1
  assert_file_not_contains "$SANDBOX/trace/resetprop-framework" ksu || return 1
  assert_file_not_contains "$SANDBOX/trace/resetprop-framework" apatch || return 1
  [ "$(grep -c -- '-t overlay' "$SANDBOX/trace/mount")" -eq 2 ] \
    || { echo "  ASSERT: Magisk did not create both owned overlays" >&2; return 1; }
  assert_file_contains "$SANDBOX/trace/resetprop" "ro.radio.noril false" || return 1
  assert_not_exists "$(RT)/.bootstrap_failed" || return 1
}

case_magisk_post_mount_is_noop() {
  harness_sh -c '
    MAGISKTMP=/data/adb/magisk
    export MAGISKTMP
    /data/adb/modules/mock_telephony/post-mount.sh
  ' || return 1
  assert_not_exists "$SANDBOX/trace/resetprop" || return 1
  assert_not_exists "$SANDBOX/trace/mount" || return 1
}

case_magisk_bind_fallback() {
  printf 'nodev tmpfs\n' > "$SANDBOX/etc/filesystems"
  harness_sh -c '
    MAGISKTMP=/data/adb/magisk
    export MAGISKTMP
    /data/adb/modules/mock_telephony/post-fs-data.sh
  ' || return 1
  assert_file_contains "$SANDBOX/trace/resetprop-framework" magisk || return 1
  assert_file_contains "$SANDBOX/trace/mount" "-t tmpfs" || return 1
  assert_file_contains "$SANDBOX/trace/mount" "--bind" || return 1
  assert_not_exists "$(RT)/.bootstrap_failed" || return 1
}

case_apatch_native_overlay_lifecycle() {
  harness_sh -c '
    APATCH=true
    export APATCH
    /data/adb/modules/mock_telephony/post-fs-data.sh
  ' || return 1
  assert_not_exists "$SANDBOX/trace/resetprop" || return 1
  : > "$SANDBOX/system/etc/permissions/mock-telephony-features.xml"
  : > "$SANDBOX/system/etc/vintf/manifest/mockmodem.radio.xml"
  harness_sh -c '
    APATCH=true
    export APATCH
    /data/adb/modules/mock_telephony/post-mount.sh
  ' || return 1
  assert_not_exists "$SANDBOX/trace/mount" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop-framework" apatch || return 1
  assert_file_not_contains "$SANDBOX/trace/resetprop-framework" ksu || return 1
  assert_file_not_contains "$SANDBOX/trace/resetprop-framework" magisk || return 1
}

case_apatch_bind_fallback() {
  printf 'nodev tmpfs\n' > "$SANDBOX/etc/filesystems"
  harness_sh -c '
    APATCH=true
    export APATCH
    /data/adb/modules/mock_telephony/post-fs-data.sh
    /data/adb/modules/mock_telephony/post-mount.sh
  ' || return 1
  assert_file_contains "$SANDBOX/trace/resetprop-framework" apatch || return 1
  assert_file_contains "$SANDBOX/trace/mount" "-t tmpfs" || return 1
  assert_file_contains "$SANDBOX/trace/mount" "--bind" || return 1
  assert_not_exists "$(RT)/.bootstrap_failed" || return 1
}

case_apatch_failure_uses_apatch_rollback() {
  set_mount_result 1
  harness_sh -c '
    APATCH=true
    export APATCH
    /data/adb/modules/mock_telephony/post-fs-data.sh
  ' || return 1
  local rc=0
  harness_sh -c '
    APATCH=true
    export APATCH
    /data/adb/modules/mock_telephony/post-mount.sh
  ' || rc=$?
  [ "$rc" -ne 0 ] || { echo "  ASSERT: APatch bootstrap failure was ignored" >&2; return 1; }
  assert_exists "$(RT)/.bootstrap_failed" || return 1
  assert_file_contains "$SANDBOX/trace/resetprop-framework" apatch || return 1
  assert_file_contains "$SANDBOX/trace/resetprop" "ro.radio.noril true" || return 1
}

case_magisk_uninstall_uses_magisk_resetprop() {
  seed_runtime radio.noril.original true
  harness_sh -c '
    MAGISKTMP=/data/adb/magisk
    export MAGISKTMP
    /data/adb/modules/mock_telephony/uninstall.sh
  ' || return 1
  assert_file_contains "$SANDBOX/trace/resetprop-framework" magisk || return 1
  assert_file_not_contains "$SANDBOX/trace/resetprop-framework" ksu || return 1
  assert_file_not_contains "$SANDBOX/trace/resetprop-framework" apatch || return 1
}

run_case framework:magisk-resetprop-preferred case_magisk_resetprop_preferred
run_case framework:apatch-resetprop-preferred case_apatch_resetprop_preferred
run_case framework:magisk-customize-keeps-skip-mount case_magisk_customize_keeps_manual_mount
run_case framework:apatch-wins-compat-environment case_apatch_wins_compat_environment
run_case framework:magisk-overlay-lifecycle case_magisk_overlay_lifecycle
run_case framework:magisk-post-mount-noop case_magisk_post_mount_is_noop
run_case framework:magisk-bind-fallback case_magisk_bind_fallback
run_case framework:apatch-native-overlay-lifecycle case_apatch_native_overlay_lifecycle
run_case framework:apatch-bind-fallback case_apatch_bind_fallback
run_case framework:apatch-rollback-path case_apatch_failure_uses_apatch_rollback
run_case framework:magisk-uninstall-resetprop case_magisk_uninstall_uses_magisk_resetprop

summary
