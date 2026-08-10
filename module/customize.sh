#!/system/bin/sh

print_msg() {
  if command -v ui_print >/dev/null 2>&1; then
    ui_print "$1"
  else
    echo "$1"
  fi
}

fail_install() {
  if command -v abort >/dev/null 2>&1; then
    abort "! $1"
    return 1
  fi
  print_msg "! $1"
  # The fallback is only for direct/test invocation. Magisk and APatch expose
  # abort(), which also removes the temporary install tree correctly.
  case "${MODPATH:-}" in
    /data/adb/modules/*|/data/adb/modules_update/*) rm -rf "$MODPATH" ;;
  esac
  case "${TMPDIR:-}" in
    /dev/tmp|/data/local/tmp/mock-telephony.*) rm -rf "$TMPDIR" ;;
  esac
  exit 1
}

DEVICE=$(getprop ro.product.device)
SDK=$(getprop ro.build.version.sdk)

print_msg "- Mock Telephony preflight: device=$DEVICE sdk=$SDK"

# Require the API floor of the frozen Radio stable AIDL v1 (AOSP android-13.0.0_r1);
case "$SDK" in
  ''|*[!0-9]*) fail_install "Could not determine the Android API level (sdk=$SDK)." ;;
esac
[ "$SDK" -ge 33 ] \
  || fail_install "This build requires Android API 33 or newer (found $SDK)."

# Telephony-stack precheck
if [ ! -f /data/adb/modules/mock_telephony/module.prop ]; then
  NORIL=$(getprop ro.radio.noril)
  HW_TELEPHONY=$(getprop ro.hardware.telephony)
  if [ "$NORIL" != "true" ] && [ -n "$HW_TELEPHONY" ]; then
    fail_install "This device already has an enabled telephony stack (ro.hardware.telephony=$HW_TELEPHONY); refusing to install."
  fi
  if [ "$NORIL" != "true" ] \
      && command -v pm >/dev/null 2>&1 \
      && pm list features 2>/dev/null | grep -Fq 'android.hardware.telephony'; then
    fail_install "This device already exposes the android.hardware.telephony feature; refusing to install."
  fi
fi

[ -d /system/etc/permissions ] \
  || fail_install "/system/etc/permissions is missing."
[ -d /system/etc/vintf/manifest ] \
  || fail_install "/system/etc/vintf/manifest is missing."

# Root-framework detection, used to emit a per-framework sepolicy.rule so no
# manager ever sees a domain type that does not exist there (ksu is KernelSU
# only; magisk is Magisk/APatch). KernelSU is the safe default.
ROOT_FRAMEWORK=kernel
if [ "${APATCH:-}" = true ]; then
  ROOT_FRAMEWORK=apatch
elif [ -n "${MAGISKTMP:-}" ]; then
  ROOT_FRAMEWORK=magisk
elif [ -n "${KSU:-}" ] && [ "$KSU" = "true" ]; then
  ROOT_FRAMEWORK=kernel
elif [ -d /data/adb/magisk ]; then
  ROOT_FRAMEWORK=magisk
elif [ -x /data/adb/ap/bin/apd ] || [ -d /data/adb/ap ]; then
  ROOT_FRAMEWORK=apatch
fi

# Injection backend: overlayfs is primary; Magisk/APatch can inject through
# their own systemless mount; otherwise post-fs-data falls back to a tmpfs+bind
# mirror. None of these need to be refused at install time.
if grep -qw overlay /proc/filesystems; then
  print_msg "- overlayfs detected (primary injection backend)"
else
  print_msg "! overlayfs not advertised; will use the tmpfs+bind fallback or the manager's systemless mount (best-effort)"
fi

write_sepolicy_rule() {
  case "$ROOT_FRAMEWORK" in
    magisk|apatch)
      cat > "$MODPATH/sepolicy.rule" <<'EOF'
allow magisk hal_radio_service:service_manager { add find };
allow magisk servicemanager:binder call;
allow su hal_radio_service:service_manager { add find };
allow su servicemanager:binder call;

allow radio hal_radio_service:service_manager find;
EOF
      ;;
    *)
      cat > "$MODPATH/sepolicy.rule" <<'EOF'
allow su hal_radio_service:service_manager { add find };
allow ksu hal_radio_service:service_manager { add find };
allow su servicemanager:binder call;
allow ksu servicemanager:binder call;

allow radio hal_radio_service:service_manager find;
EOF
      ;;
  esac
  chmod 644 "$MODPATH/sepolicy.rule"
  print_msg "- sepolicy.rule generated for root framework: $ROOT_FRAMEWORK"
}

# The shipped static sepolicy.rule holds the KernelSU default; regenerate it
# for the detected framework so installs on Magisk/APatch never load the ksu
# domain. MODPATH is set by the module installers (empty in the test sandbox).
if [ -n "${MODPATH:-}" ]; then
  write_sepolicy_rule
  if [ "$ROOT_FRAMEWORK" = apatch ] && grep -qw overlay /proc/filesystems; then
    # APatch can mount the module's system tree after post-fs-data. Let its
    # native overlay backend own these files, then validate them in post-mount.
    rm -f "$MODPATH/skip_mount"
    print_msg "- APatch native system overlay enabled"
  fi
fi

print_msg "- Preflight passed"
