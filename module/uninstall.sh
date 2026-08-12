#!/system/bin/sh
#
# Undo overlay mounts before the module directory is removed.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
init_runtime
RESETPROP=$(find_resetprop)

echo "[uninstall] removing overlays $(date)" >> "$LOG"

# Signal self-healing loops (daemon watchdog, supervisor adopt) to stop so
# nothing revives the tree while we tear it down.
: > "$RUNTIME/.uninstalling"
chmod 600 "$RUNTIME/.uninstalling"

SPID=$(cat "$RUNTIME/supervisor.pid" 2>/dev/null)
if process_matches "$SPID" "$MODDIR/mockmodem-supervisor.sh"; then
  kill "$SPID" 2>>"$LOG" || true
  echo "[uninstall] stopped supervisor" >> "$LOG"
fi

MPID=$(cat "$RUNTIME/mockmodem.pid" 2>/dev/null)
if process_matches "$MPID" mockmodem; then
  kill "$MPID" 2>>"$LOG" || true
  echo "[uninstall] stopped mockmodem" >> "$LOG"
fi

if owned_overlay /system/etc/vintf/manifest "$RUNTIME/vintf-system-upper"; then
  umount /system/etc/vintf/manifest 2>>"$LOG" \
    && echo "[uninstall] unmounted owned VINTF overlay" >> "$LOG"
fi

if owned_overlay /system/etc/permissions "$RUNTIME/permissions-upper"; then
  umount /system/etc/permissions 2>>"$LOG" \
    && echo "[uninstall] unmounted owned permissions overlay" >> "$LOG"
fi

# No-overlayfs backend: unmount any owned bind mirrors and their tmpfs scratch
# so the .runtime tree below can be removed cleanly.
for target in /system/etc/permissions /system/etc/vintf/manifest; do
  if owned_bind "$target"; then
    umount "$target" 2>>"$LOG" \
      && echo "[uninstall] unmounted owned bind mirror $target" >> "$LOG"
  fi
  mirror=$(bind_mirror_path "$target")
  if [ -d "$mirror" ] && mountpoint -q "$mirror" 2>/dev/null; then
    umount "$mirror" 2>>"$LOG" || true
  fi
done

if [ -x "$RESETPROP" ]; then
  if [ -f "$RUNTIME/radio.noril.original" ]; then
    original=$(cat "$RUNTIME/radio.noril.original" 2>/dev/null)
    case "$original" in
      true|false) "$RESETPROP" -n ro.radio.noril "$original" || true ;;
    esac
  fi
fi

echo "[uninstall] done" >> "$LOG"

if [ -d "$MODDIR/.runtime" ]; then
  rm -rf "$MODDIR/.runtime"
fi
