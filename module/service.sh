#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
init_runtime

SUPERVISOR_PIDFILE="$RUNTIME/supervisor.pid"

module_log service "stage ran $(date)"

if [ -f "$RUNTIME/.bootstrap_failed" ]; then
  module_log service "bootstrap prerequisites failed; refusing to start daemon"
  exit 1
fi

if overlay_supported; then
  if [ "${APATCH:-}" = true ] \
      && [ -f /system/etc/permissions/mock-telephony-features.xml ] \
      && [ -f /system/etc/vintf/manifest/mockmodem.radio.xml ]; then
    module_log service "required APatch manager injections are present"
  elif ! owned_overlay /system/etc/permissions "$RUNTIME/permissions-upper" \
      || ! owned_overlay /system/etc/vintf/manifest "$RUNTIME/vintf-system-upper"; then
    module_log service "required overlays are not owned; refusing to start daemon"
    exit 1
  fi
else
  # No-overlayfs backend: the injections are either a manager systemless mount
  # or the module's tmpfs+bind mirror. Both surface the files at these paths.
  if [ ! -f /system/etc/permissions/mock-telephony-features.xml ] \
      || [ ! -f /system/etc/vintf/manifest/mockmodem.radio.xml ]; then
    module_log service "required injections are not present; refusing to start daemon"
    exit 1
  fi
fi

SUPERVISOR_PID=$(cat "$SUPERVISOR_PIDFILE" 2>/dev/null)
if ! process_matches "$SUPERVISOR_PID" "$MODDIR/mockmodem-supervisor.sh"; then
  nohup /system/bin/sh "$MODDIR/mockmodem-supervisor.sh" >> "$LOG" 2>&1 &
  SUPERVISOR_PID=$!
  echo "$SUPERVISOR_PID" > "$SUPERVISOR_PIDFILE"
  chmod 600 "$SUPERVISOR_PIDFILE"
  module_log service "started supervisor pid $SUPERVISOR_PID"
else
  module_log service "supervisor already running pid $SUPERVISOR_PID"
fi

module_log service "required injections ready: permissions and VINTF"
