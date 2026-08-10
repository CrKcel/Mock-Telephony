#!/system/bin/sh

RUNTIME="$MODDIR/.runtime"
LOG="$RUNTIME/mock_telephony.log"

init_runtime() {
  mkdir -p "$RUNTIME"
  chmod 700 "$RUNTIME"
  touch "$LOG"
  chmod 600 "$LOG"

  if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null)" -gt 524288 ]; then
    mv -f "$LOG" "$LOG.1"
    touch "$LOG"
    chmod 600 "$LOG" "$LOG.1"
  fi
}

module_log() {
  echo "[$1] $2" >> "$LOG"
}

process_matches() {
  local pid="$1" expected="$2"
  [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] \
    && tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq "$expected"
}

owned_overlay() {
  local target="$1" upper="$2"
  awk -v target="$target" -v upper="upperdir=$upper" '
    $5 == target {
      for (i = 1; i <= NF; i++) if (index($i, upper) != 0) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' /proc/self/mountinfo
}

# Resolve the resetprop binary across root frameworks (KernelSU, Magisk,
# APatch). Echoes the first usable absolute path, or nothing when none exists.
# post-fs-data and uninstall treat a missing binary as "cannot restore/apply
# properties" and fail or skip accordingly.
find_resetprop() {
  local candidates candidate
  candidates=''
  case "${APATCH:-}" in
    true|1) candidates="/data/adb/ap/bin/resetprop" ;;
  esac
  if [ -n "${MAGISKTMP:-}" ]; then
    candidates="$candidates /data/adb/magisk/resetprop"
  fi
  if [ "${KSU:-}" = true ]; then
    candidates="$candidates /data/adb/ksu/bin/resetprop"
  fi
  candidates="$candidates /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop /data/adb/ap/bin/resetprop"
  for candidate in $candidates; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# True when the running kernel advertises overlayfs: the module's primary
# systemless-injection backend. When absent the module falls back to a
# tmpfs+bind mirror (see bind_mirror in post-fs-data.sh) or to the manager's
# own systemless mount.
overlay_supported() {
  grep -qw overlay /proc/filesystems
}

# Path of the tmpfs bind-mirror used for a target system dir (no-overlayfs
# backend). Derived from the full target path so both bind_mirror (in
# post-fs-data.sh) and the uninstall/rollback paths agree on the name.
bind_mirror_path() {
  printf '%s\n' "$RUNTIME/bind-$(printf '%s' "${1#/}" | tr '/' '-')"
}

# True when this module owns a bind-mirror mount over $1 (the no-overlayfs
# injection backend). Matches the mirror's tmpfs source under .runtime in
# /proc/self/mountinfo.
owned_bind() {
  local target="$1"
  local mirror
  mirror=$(bind_mirror_path "$target")
  [ -n "$mirror" ] || return 1
  awk -v target="$target" -v mirror="$mirror" '
    $5 == target && index($0, mirror) != 0 { found = 1 }
    END { exit(found ? 0 : 1) }
  ' /proc/self/mountinfo
}
