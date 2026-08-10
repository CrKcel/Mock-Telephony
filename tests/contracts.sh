#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="$PROJECT_ROOT/daemon/src/main/java/android/telephony/mockmodem"

fail() {
  echo "module contract failure: $*" >&2
  exit 1
}

post_fs_data="$PROJECT_ROOT/module/post-fs-data.sh"
bootstrap="$PROJECT_ROOT/module/bootstrap.sh"
post_mount="$PROJECT_ROOT/module/post-mount.sh"
service_script="$PROJECT_ROOT/module/service.sh"
uninstall_script="$PROJECT_ROOT/module/uninstall.sh"
rg -q 'FAILED_MARKER=.*bootstrap_failed' "$bootstrap" \
  || fail "post-fs-data does not create a bootstrap failure marker"
rg -q 'restore_original_properties' "$bootstrap" \
  || fail "post-fs-data does not restore properties on prerequisite failure"
rg -q 'PERMISSIONS_READY' "$bootstrap" \
  || fail "post-fs-data does not gate activation on permissions overlay readiness"
rg -q 'VINTF_READY' "$bootstrap" \
  || fail "post-fs-data does not gate activation on VINTF overlay readiness"
rg -q 'bootstrap_apply' "$post_fs_data" \
  || fail "post-fs-data does not invoke the bootstrap transaction"
rg -q 'bootstrap_apply' "$post_mount" \
  || fail "post-mount does not invoke the APatch bootstrap transaction"
rg -q 'bootstrap_failed' "$service_script" \
  || fail "service.sh does not block startup after bootstrap failure"
rg -q 'persist\.radio\.allow_mock_modem true' "$bootstrap" \
  || fail "post-fs-data must enable the mock modem property for Shizuku/ADB"
rg -q 'set-modem-service' "$uninstall_script" \
  || fail "uninstall.sh must restore the default modem service"

# Install preflight must cancel on a device that already has telephony enabled.
rg -q 'ro\.radio\.noril' "$PROJECT_ROOT/module/customize.sh" \
  || fail "customize.sh does not inspect the no-RIL gate"
rg -q 'ro\.hardware\.telephony' "$PROJECT_ROOT/module/customize.sh" \
  || fail "customize.sh does not detect existing telephony hardware"
rg -q 'pm list features.*android\.hardware\.telephony' "$PROJECT_ROOT/module/customize.sh" \
  || fail "customize.sh does not detect the telephony feature"
rg -q 'refusing to install' "$PROJECT_ROOT/module/customize.sh" \
  || fail "customize.sh does not cancel install on an enabled telephony stack"
rg -q 'command -v abort' "$PROJECT_ROOT/module/customize.sh" \
  || fail "customize.sh does not use the framework abort cleanup path"

adb_smoke="$PROJECT_ROOT/tools/adb-smoke.sh"
rg -q '/data/adb/ap/bin/apd' "$adb_smoke" \
  || fail "adb smoke does not detect the APatch runtime path"
if rg -q 'rm -rf /data/adb/modules/mock_telephony' "$adb_smoke"; then
  fail "adb smoke bypasses the module uninstall lifecycle"
fi

if rg -q '^import dev\.mocktelephony' "$BOOTSTRAP"; then
  fail "bootstrap sources must not import APK packages"
fi
# sepolicy is trimmed to the minimal working set: no blanket
# service_manager:service_manager find grants (daemon/framework get only the
# specific hal_radio_service grants they need).
sepolicy_rule="$PROJECT_ROOT/module/sepolicy.rule"
if rg -q 'service_manager:service_manager find' "$sepolicy_rule"; then
  fail "sepolicy.rule must not grant blanket service_manager find"
fi
# ... and the specific grants the daemon/framework rely on are all present.
rg -q 'allow su hal_radio_service:service_manager.*add' "$sepolicy_rule" \
  || fail "sepolicy.rule must let su add hal_radio_service"
rg -q 'allow ksu hal_radio_service:service_manager.*add' "$sepolicy_rule" \
  || fail "sepolicy.rule must let ksu add hal_radio_service"
rg -q 'allow su servicemanager:binder call' "$sepolicy_rule" \
  || fail "sepolicy.rule must let su call servicemanager"
rg -q 'allow ksu servicemanager:binder call' "$sepolicy_rule" \
  || fail "sepolicy.rule must let ksu call servicemanager"
rg -q 'allow radio hal_radio_service:service_manager.*find' "$sepolicy_rule" \
  || fail "sepolicy.rule must let radio find hal_radio_service"
# Install-time sepolicy.rule regeneration keeps each root framework from ever
# loading a domain type that does not exist there (ksu is KernelSU only; magisk
# is Magisk/APatch).
rg -q 'sepolicy\.rule' "$PROJECT_ROOT/module/customize.sh" \
  || fail "customize.sh must generate a per-framework sepolicy.rule"
# The no-overlayfs injection backend must stay present so the module can run on
# kernels without overlayfs (tmpfs mirror + bind).
rg -q 'mount --bind' "$bootstrap" \
  || fail "post-fs-data.sh must provide a no-overlayfs bind fallback"
for entry in MockModemMain StandaloneRadioRegistrar; do
  [ -f "$BOOTSTRAP/$entry.java" ] || fail "missing bootstrap entry $entry"
done

# Module daemon contracts run against the module-owned daemon tree.
"$PROJECT_ROOT/tests/runtime-contracts.sh"

echo "Module contract checks passed"
