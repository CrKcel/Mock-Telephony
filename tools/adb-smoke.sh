#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/build-env.sh
. "$SCRIPT_DIR/lib/build-env.sh"
load_aidl_version

ADB_BIN="${ADB_BIN:-adb}"
RESTART_DAEMON=0
RESTART_PHONE=0
FAIL_BOOTSTRAP=0
UNINSTALL_REINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --restart-daemon) RESTART_DAEMON=1 ;;
    --restart-phone) RESTART_PHONE=1 ;;
    --fail-bootstrap) FAIL_BOOTSTRAP=1 ;;
    --uninstall-reinstall) UNINSTALL_REINSTALL=1 ;;
    *)
      echo "usage: $0 [--restart-daemon] [--restart-phone] [--fail-bootstrap] [--uninstall-reinstall]" >&2
      exit 2
      ;;
  esac
done

adb_cmd=("$ADB_BIN")
if [ -n "${ANDROID_SERIAL:-}" ]; then
  adb_cmd+=( -s "$ANDROID_SERIAL" )
fi

die() { echo "ADB smoke failure: $*" >&2; exit 1; }
shell() { "${adb_cmd[@]}" shell "$@"; }
root_shell() { shell su -c "$1"; }

# Detect the root framework (KernelSU / Magisk / APatch) from the su context,
# falling back to the manager's /data/adb data dir. KernelSU is the validated
# path; Magisk/APatch are best-effort and unverified on real hardware.
detect_framework() {
  if root_shell '[ -x /data/adb/ap/bin/apd ] && echo yes' | grep -q yes; then
    echo apatch
    return 0
  fi
  local ctx
  ctx=$(root_shell 'id' 2>/dev/null | tr -d '\r' || true)
  case "$ctx" in
    *u:r:ksu:s0*) echo kernel; return 0 ;;
    *u:r:magisk:s0*) echo magisk; return 0 ;;
    *apatch*) echo apatch; return 0 ;;
  esac
  if root_shell '[ -e /data/adb/ksu ] && echo yes' | grep -q yes; then
    echo kernel
    return 0
  fi
  if root_shell '[ -e /data/adb/magisk ] && echo yes' | grep -q yes; then
    echo magisk
    return 0
  fi
  echo unknown
}

# Framework-aware module install/uninstall commands.
manager_install() {
  local package="$1"
  case "$FRAMEWORK" in
    kernel) root_shell "/data/adb/ksud module install $package" ;;
    magisk) root_shell "/data/adb/magisk/magisk --install-module $package" ;;
    apatch) root_shell "/data/adb/ap/bin/apd module install $package" ;;
    *) die "unsupported root framework: $FRAMEWORK" ;;
  esac
}

manager_uninstall() {
  case "$FRAMEWORK" in
    kernel) root_shell "/data/adb/ksud module uninstall mock_telephony" ;;
    magisk) root_shell "touch /data/adb/modules/mock_telephony/remove" ;;
    apatch) root_shell "/data/adb/ap/bin/apd module uninstall mock_telephony" ;;
    *) die "unsupported root framework: $FRAMEWORK" ;;
  esac
}

# Let offline tests load framework detection and manager command helpers
# without probing ADB or requiring a connected device.
if [ "${ADB_SMOKE_LIB_ONLY:-0}" = 1 ]; then
  return 0
fi

[ "$("${adb_cmd[@]}" get-state)" = device ] || die "device is not connected"
sdk=$(shell getprop ro.build.version.sdk | tr -d '\r')
case "$sdk" in
  ''|*[!0-9]*) die "could not determine Android API level (sdk=$sdk)" ;;
esac
[ "$sdk" -ge 33 ] || die "device API level $sdk is below the API 33 floor"

FRAMEWORK=$(detect_framework)
overlay_present=$(shell "grep -qw overlay /proc/filesystems && echo yes || echo no" | tr -d '\r')
echo "ADB smoke: sdk=$sdk framework=$FRAMEWORK overlayfs=$overlay_present"
[ "$FRAMEWORK" != unknown ] || die "could not detect the root framework"

reboot_and_wait() {
  "${adb_cmd[@]}" reboot
  "${adb_cmd[@]}" wait-for-device
  for _ in $(seq 1 60); do
    booted=$(shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
    if [ "$booted" = "1" ]; then
      return 0
    fi
    sleep 5
  done
  die "device did not finish booting"
}

standard_checks() {
  # Android 15+ advances the terminal SIM state from READY to LOADED once every
  # IccRecords EF has loaded (the static mock SIM now completes its ICCID read),
  # so both are valid terminal states for the bootstrap.
  for _ in $(seq 1 30); do
    phone_state=$(shell service check phone 2>&1 | tr -d '\r')
    sim_state=$(shell getprop gsm.sim.state | tr -d '\r')
    if [ "$phone_state" = 'Service phone: found' ] \
      && { [ "$sim_state" = READY ] || [ "$sim_state" = LOADED ]; }; then
      break
    fi
    sleep 1
  done
  [ "$phone_state" = 'Service phone: found' ] || die "phone service is unavailable"
  case "$sim_state" in
    READY|LOADED) ;;
    *) die "SIM state is $sim_state (static bootstrap mock SIM is not READY/LOADED)" ;;
  esac

  hal_count=$(shell service list | grep -Ec \
    'android\.hardware\.radio\.(config|data|messaging|modem|network|sim|voice)\.IRadio')
  [ "$hal_count" -eq 7 ] || die "expected 7 Radio HALs, got $hal_count"

  hal_specs=(
    'config IRadioConfig default'
    'data IRadioData slot1'
    'messaging IRadioMessaging slot1'
    'modem IRadioModem slot1'
    'network IRadioNetwork slot1'
    'sim IRadioSim slot1'
    'voice IRadioVoice slot1'
  )
  for spec in "${hal_specs[@]}"; do
    read -r package_name interface_name instance <<<"$spec"
    service_name="android.hardware.radio.$package_name.$interface_name/$instance"
    hash_var="AIDL_HASH_${package_name^^}"
    actual_hash=$(shell service call "$service_name" 16777214 \
      | sed -n "s/.*'\(.*\)'.*/\1/p" | tr -d "(). '[:space:]")
    [ "$actual_hash" = "${!hash_var}" ] \
      || die "$package_name hash mismatch: ${actual_hash:-empty}"
    shell service call "$service_name" 16777215 | grep -q '00000001' \
      || die "$package_name does not report AIDL version 1"
  done

  # Aligns with MockModemConfigInterface.DEFAULT_BASEBAND_VERSION
  [ "$(shell getprop gsm.version.baseband | tr -d '\r')" = MPSS.DI.3.0.c1.7-00001-1 ] \
    || die "unexpected baseband"
  registry=$(shell dumpsys telephony.registry)
  grep -q 'mVoiceRegState=0(IN_SERVICE)' <<<"$registry" || die "voice is not IN_SERVICE"
  grep -q 'mDataRegState=0(IN_SERVICE)' <<<"$registry" || die "data registration is not IN_SERVICE"
  grep -q 'mDataConnectionState=-1' <<<"$registry" || die "data connection was unexpectedly created"

  # The injected files must be visible in the system tree via whichever backend
  # is in effect (module overlay, manager systemless mount, or tmpfs+bind).
  shell test -f /system/etc/permissions/mock-telephony-features.xml \
    || die "feature XML not injected into /system/etc/permissions"
  shell test -f /system/etc/vintf/manifest/mockmodem.radio.xml \
    || die "VINTF fragment not injected into /system/etc/vintf/manifest"

  # Bootstrap properties took effect, so the resolved resetprop binary worked.
  [ "$(shell getprop ro.radio.noril | tr -d '\r')" = false ] \
    || die "ro.radio.noril is not false after bootstrap"

  # The on-device sepolicy.rule must match the detected framework: KernelSU
  # keeps the ksu domain; Magisk/APatch must never load it (unknown type).
  local sepolicy
  sepolicy=$(root_shell 'cat /data/adb/modules/mock_telephony/sepolicy.rule' \
    2>/dev/null | tr -d '\r' || true)
  case "$FRAMEWORK" in
    kernel)
      grep -q 'allow ksu hal_radio_service' <<<"$sepolicy" \
        || die "on-device sepolicy.rule lacks the ksu domain (framework=$FRAMEWORK)"
      ;;
    magisk|apatch)
      grep -q 'allow magisk hal_radio_service' <<<"$sepolicy" \
        || die "on-device sepolicy.rule lacks the magisk domain (framework=$FRAMEWORK)"
      if grep -q 'allow ksu ' <<<"$sepolicy"; then
        die "on-device sepolicy.rule leaks the KernelSU-only ksu domain onto $FRAMEWORK"
      fi
      ;;
  esac

  echo "ADB smoke passed: phone found, SIM $sim_state, 7 HALs, voice/data IN_SERVICE (framework=$FRAMEWORK)"
}

# Deliberately break a bootstrap precondition, reboot, assert the failure
# rollback (marker + property restore + no HALs), then restore and assert full
# recovery.
fail_bootstrap() {
  local xml="/data/adb/modules/mock_telephony/system/etc/permissions/mock-telephony-features.xml"
  if [ "$(root_shell "test -f $xml && echo yes" | tr -d '\r')" != yes ]; then
    die "module feature XML not found; cannot break bootstrap"
  fi

  echo "[fail-bootstrap] moving feature XML aside and rebooting"
  root_shell "mv $xml ${xml}.bak" || die "failed to move feature XML aside"
  reboot_and_wait

  echo "[fail-bootstrap] asserting rollback after broken bootstrap"
  marker=$(root_shell 'test -f /data/adb/modules/mock_telephony/.runtime/.bootstrap_failed && echo yes' \
    | tr -d '\r')
  [ "$marker" = yes ] || die "no .bootstrap_failed marker after broken bootstrap"
  noril=$(shell getprop ro.radio.noril | tr -d '\r')
  [ "$noril" != false ] || die "ro.radio.noril was not restored (still false)"
  hal_count=$(shell service list 2>/dev/null | grep -Ec 'android\.hardware\.radio\.' || true)
  [ "$hal_count" -eq 0 ] || die "radio HALs still registered after failed bootstrap: $hal_count"
  log_all=$(root_shell 'cat /data/adb/modules/mock_telephony/.runtime/mock_telephony.log' \
    2>/dev/null | tr -d '\r' || true)
  grep -q 'bootstrap prerequisites failed' <<<"$log_all" || die "module log lacks the failure record"
  echo "[fail-bootstrap] rollback verified: marker present, properties restored, no HALs"

  echo "[fail-bootstrap] restoring feature XML and rebooting"
  root_shell "mv ${xml}.bak $xml" || die "failed to restore feature XML"
  reboot_and_wait

  echo "[fail-bootstrap] asserting full recovery"
  standard_checks
}

# Uninstall -> reboot -> assert clean state -> reinstall -> reboot -> assert full recovery.
uninstall_reinstall() {
  local package="$PROJECT_ROOT/dist/mock-telephony-$(module_property version).zip"
  [ -f "$package" ] || die "no local package: $package"

  echo "[uninstall-reinstall] uninstalling module and rebooting"
  manager_uninstall || die "module uninstall failed"
  reboot_and_wait

  echo "[uninstall-reinstall] asserting clean state after uninstall"
  if [ "$(root_shell 'test -d /data/adb/modules/mock_telephony && echo yes' | tr -d '\r')" = yes ]; then
    die "module directory still present after uninstall"
  fi
  hal_count=$(shell service list 2>/dev/null | grep -Ec 'android\.hardware\.radio\.' || true)
  [ "$hal_count" -eq 0 ] || die "radio HALs still registered after uninstall: $hal_count"
  echo "[uninstall-reinstall] clean state verified"

  echo "[uninstall-reinstall] reinstalling package and rebooting"
  "${adb_cmd[@]}" push "$package" /data/local/tmp/ >/dev/null
  manager_install "/data/local/tmp/$(basename "$package")" \
    || die "module reinstall failed"
  reboot_and_wait

  echo "[uninstall-reinstall] asserting full recovery"
  standard_checks
}

if [ "$FAIL_BOOTSTRAP" -eq 1 ]; then
  fail_bootstrap
elif [ "$UNINSTALL_REINSTALL" -eq 1 ]; then
  uninstall_reinstall
else
  if [ "$RESTART_DAEMON" -eq 1 ]; then
    old_pid=$(root_shell 'cat /data/adb/modules/mock_telephony/.runtime/mockmodem.pid' \
      | tr -d '\r')
    [ -n "$old_pid" ] || die "no running mockmodem daemon to restart (pidfile missing)"
    root_shell "kill $old_pid"
    new_pid=""
    for _ in $(seq 1 30); do
      candidate=$(
        root_shell 'cat /data/adb/modules/mock_telephony/.runtime/mockmodem.pid 2>/dev/null' \
          2>/dev/null || true
      )
      candidate=$(printf '%s' "$candidate" | tr -d '\r')
      if [ -n "$candidate" ] && [ "$candidate" != "$old_pid" ]; then
        new_pid="$candidate"
        break
      fi
      sleep 1
    done
    [ -n "$new_pid" ] || die "supervisor did not replace daemon PID $old_pid"
    echo "daemon recovery: $old_pid -> $new_pid"
  fi

  if [ "$RESTART_PHONE" -eq 1 ]; then
    old_phone=$(root_shell 'pidof com.android.phone' | tr -d '\r')
    [ -n "$old_phone" ] || die "com.android.phone is not running; cannot restart"
    root_shell "kill $old_phone"
    new_phone=""
    for _ in $(seq 1 30); do
      new_phone=$(root_shell 'pidof com.android.phone' 2>/dev/null || true)
      new_phone=$(printf '%s' "$new_phone" | tr -d '\r')
      [ -n "$new_phone" ] && [ "$new_phone" != "$old_phone" ] && break
      sleep 1
    done
    [ -n "${new_phone:-}" ] && [ "$new_phone" != "$old_phone" ] \
      || die "com.android.phone did not restart"
    echo "phone recovery: $old_phone -> $new_phone"
  fi

  standard_checks
fi
