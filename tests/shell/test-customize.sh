#!/usr/bin/env bash
# Behavioral tests for module/customize.sh: install preflight gates.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

# Run customize in the sandbox; captures its output to $SANDBOX/out.txt and
# returns its exit code.
run_customize() {
  local rc=0 out
  out=$(harness_run customize.sh 2>&1) || rc=$?
  printf '%s\n' "$out" > "$SANDBOX/out.txt"
  return "$rc"
}

case_sdk_too_low() {
  set_prop ro.build.version.sdk 32
  if run_customize; then
    echo "  ASSERT: expected install to be refused for API 32" >&2
    return 1
  fi
  assert_file_contains "$SANDBOX/out.txt" "requires Android API 33" || return 1
  return 0
}

case_framework_abort_used() {
  set_prop ro.build.version.sdk 32
  local out rc=0
  out=$(harness_sh -c 'abort() { echo "abort:$*"; exit 42; }; . /data/adb/modules/mock_telephony/customize.sh' 2>&1) || rc=$?
  [ "$rc" -eq 42 ] || { echo "  ASSERT: expected abort rc=42, got $rc" >&2; return 1; }
  printf '%s\n' "$out" | grep -Fq 'abort:! This build requires Android API 33' \
    || { echo "  ASSERT: framework abort was not called" >&2; return 1; }
  return 0
}

case_sdk_invalid() {
  set_prop ro.build.version.sdk "abc"
  if run_customize; then
    echo "  ASSERT: expected install to be refused for invalid SDK" >&2
    return 1
  fi
  assert_file_contains "$SANDBOX/out.txt" "Could not determine the Android API level" || return 1
  return 0
}

case_telephony_hw_refused() {
  set_prop ro.build.version.sdk 36
  set_prop ro.hardware.telephony mtk
  remove_module_prop   # fresh install, not an upgrade
  if run_customize; then
    echo "  ASSERT: expected refusal on existing telephony hardware" >&2
    return 1
  fi
  assert_file_contains "$SANDBOX/out.txt" "already has an enabled telephony stack" || return 1
  return 0
}

case_telephony_feature_refused() {
  set_prop ro.build.version.sdk 36
  set_pm_features android.hardware.telephony
  remove_module_prop
  if run_customize; then
    echo "  ASSERT: expected refusal on telephony feature" >&2
    return 1
  fi
  assert_file_contains "$SANDBOX/out.txt" "android.hardware.telephony feature" || return 1
  return 0
}

case_upgrade_allowed() {
  set_prop ro.build.version.sdk 36
  set_prop ro.hardware.telephony mtk
  # module.prop is present -> upgrade of an installed module is allowed.
  if ! run_customize; then
    echo "  ASSERT: expected upgrade to be allowed" >&2
    return 1
  fi
  assert_file_contains "$SANDBOX/out.txt" "Preflight passed" || return 1
  return 0
}

case_noril_allowed() {
  set_prop ro.build.version.sdk 36
  set_prop ro.radio.noril true
  set_prop ro.hardware.telephony mtk
  if ! run_customize; then
    echo "  ASSERT: expected noril=true device to pass" >&2
    return 1
  fi
  assert_file_contains "$SANDBOX/out.txt" "Preflight passed" || return 1
  return 0
}

case_no_overlayfs_best_effort() {
  set_prop ro.build.version.sdk 36
  # /proc/filesystems no longer advertises overlayfs: install proceeds, falling
  # back to tmpfs+bind or the manager's systemless mount.
  printf 'nodev tmpfs\n' > "$SANDBOX/etc/filesystems"
  if ! run_customize; then
    echo "  ASSERT: expected install to proceed without overlayfs" >&2
    return 1
  fi
  assert_file_contains "$SANDBOX/out.txt" "tmpfs+bind" || return 1
  return 0
}

case_sepolicy_kernel_domain() {
  set_prop ro.build.version.sdk 36
  local out rc=0
  out=$(harness_sh -c 'MODPATH=/data/adb/modules/mock_telephony KSU=true /data/adb/modules/mock_telephony/customize.sh' 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || { echo "  ASSERT: customize rc=$rc" >&2; return 1; }
  # KernelSU default: ksu domain present, radio find present, no magisk leak.
  assert_file_contains "$SANDBOX/data/adb/modules/mock_telephony/sepolicy.rule" \
    "allow ksu hal_radio_service" || return 1
  assert_file_contains "$SANDBOX/data/adb/modules/mock_telephony/sepolicy.rule" \
    "allow radio hal_radio_service" || return 1
  if grep -q 'allow magisk' "$SANDBOX/data/adb/modules/mock_telephony/sepolicy.rule"; then
    echo "  ASSERT: magisk domain leaked into KernelSU sepolicy" >&2
    return 1
  fi
  return 0
}

case_sepolicy_magisk_domain() {
  set_prop ro.build.version.sdk 36
  local out rc=0
  out=$(harness_sh -c 'MODPATH=/data/adb/modules/mock_telephony MAGISKTMP=/data/adb/magisk /data/adb/modules/mock_telephony/customize.sh' 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || { echo "  ASSERT: customize rc=$rc" >&2; return 1; }
  # Magisk: magisk domain present, and the KernelSU-only ksu domain must not
  # leak into a policy magiskpolicy would fail to resolve.
  assert_file_contains "$SANDBOX/data/adb/modules/mock_telephony/sepolicy.rule" \
    "allow magisk hal_radio_service" || return 1
  if grep -q 'allow ksu' "$SANDBOX/data/adb/modules/mock_telephony/sepolicy.rule"; then
    echo "  ASSERT: ksu domain leaked into Magisk sepolicy" >&2
    return 1
  fi
  return 0
}

case_sepolicy_apatch_domain_and_mount_mode() {
  set_prop ro.build.version.sdk 36
  local out rc=0
  out=$(harness_sh -c 'MODPATH=/data/adb/modules/mock_telephony APATCH=true /data/adb/modules/mock_telephony/customize.sh' 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || { echo "  ASSERT: customize rc=$rc" >&2; return 1; }
  assert_file_contains "$SANDBOX/data/adb/modules/mock_telephony/sepolicy.rule" \
    "allow magisk hal_radio_service" || return 1
  assert_not_exists "$SANDBOX/data/adb/modules/mock_telephony/skip_mount" || return 1
  printf '%s\n' "$out" | grep -Fq "APatch native system overlay" \
    || { echo "  ASSERT: APatch mount mode was not reported" >&2; return 1; }
  return 0
}

case_apatch_no_overlay_keeps_manual_mount() {
  set_prop ro.build.version.sdk 36
  printf 'nodev tmpfs\n' > "$SANDBOX/etc/filesystems"
  local out rc=0
  out=$(harness_sh -c 'MODPATH=/data/adb/modules/mock_telephony APATCH=true /data/adb/modules/mock_telephony/customize.sh' 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || { echo "  ASSERT: customize rc=$rc" >&2; return 1; }
  assert_exists "$SANDBOX/data/adb/modules/mock_telephony/skip_mount" || return 1
  printf '%s\n' "$out" | grep -Fq "tmpfs+bind fallback" \
    || { echo "  ASSERT: APatch fallback mode was not reported" >&2; return 1; }
  return 0
}

case_permissions_dir_missing() {
  set_prop ro.build.version.sdk 36
  rm -rf "$SANDBOX/system/etc/permissions"
  if run_customize; then
    echo "  ASSERT: expected install to be refused without permissions dir" >&2
    return 1
  fi
  assert_file_contains "$SANDBOX/out.txt" "/system/etc/permissions is missing" || return 1
  return 0
}

case_vintf_dir_missing() {
  set_prop ro.build.version.sdk 36
  rm -rf "$SANDBOX/system/etc/vintf/manifest"
  if run_customize; then
    echo "  ASSERT: expected install to be refused without vintf dir" >&2
    return 1
  fi
  assert_file_contains "$SANDBOX/out.txt" "/system/etc/vintf/manifest is missing" || return 1
  return 0
}

run_case customize:sdk-too-low case_sdk_too_low
run_case customize:framework-abort-used case_framework_abort_used
run_case customize:sdk-invalid case_sdk_invalid
run_case customize:telephony-hw-refused case_telephony_hw_refused
run_case customize:telephony-feature-refused case_telephony_feature_refused
run_case customize:upgrade-allowed case_upgrade_allowed
run_case customize:noril-allowed case_noril_allowed
run_case customize:no-overlayfs-best-effort case_no_overlayfs_best_effort
run_case customize:sepolicy-kernel-domain case_sepolicy_kernel_domain
run_case customize:sepolicy-magisk-domain case_sepolicy_magisk_domain
run_case customize:sepolicy-apatch-domain-and-mount-mode case_sepolicy_apatch_domain_and_mount_mode
run_case customize:apatch-no-overlay-keeps-manual-mount case_apatch_no_overlay_keeps_manual_mount
run_case customize:permissions-dir-missing case_permissions_dir_missing
run_case customize:vintf-dir-missing case_vintf_dir_missing

summary
