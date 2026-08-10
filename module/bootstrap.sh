#!/system/bin/sh
# Shared bootstrap transaction for post-fs-data and APatch post-mount.

. "$MODDIR/common.sh"
RESETPROP=$(find_resetprop)
init_runtime

BOOTSTRAP_STAGE=${BOOTSTRAP_STAGE:-${1:-apply}}
echo "=== $BOOTSTRAP_STAGE $(date) ===" >> "$LOG"

FAILED_MARKER="$RUNTIME/.bootstrap_failed"
NORIL_ORIGINAL="$RUNTIME/radio.noril.original"

save_original_properties() {
  if [ ! -f "$NORIL_ORIGINAL" ]; then
    original=$(getprop ro.radio.noril)
    case "$original" in
      true|false) ;;
      *) original=true ;;
    esac
    printf '%s\n' "$original" > "$NORIL_ORIGINAL"
    chmod 600 "$NORIL_ORIGINAL"
  fi
}

restore_original_properties() {
  if [ -x "$RESETPROP" ] && [ -f "$NORIL_ORIGINAL" ]; then
    original=$(cat "$NORIL_ORIGINAL" 2>/dev/null)
    case "$original" in
      true|false) ;;
      *) original=true ;;
    esac
    "$RESETPROP" -n ro.radio.noril "$original" || true
  fi
  if [ -x "$RESETPROP" ]; then
    "$RESETPROP" -n persist.radio.allow_mock_modem false || true
  fi
}

bootstrap_prepare() {
  rm -f "$FAILED_MARKER"
  save_original_properties
  module_log "$BOOTSTRAP_STAGE" "prepared"
}

overlay_mount() {
  local target="$1" upper="$2" work="$3"
  OVERLAY_MOUNTED_THIS_RUN=0
  mkdir -p "$upper" "$work"
  chmod 755 "$upper"
  chmod 700 "$work"
  if owned_overlay "$target" "$upper"; then
    module_log "$BOOTSTRAP_STAGE" "overlay already owned: $target"
    return 0
  fi
  if mountpoint -q "$target" 2>/dev/null; then
    module_log "$BOOTSTRAP_STAGE" "overlay conflict, refusing foreign mount: $target"
    return 1
  fi
  if mount -t overlay overlay \
      -o "lowerdir=$target,upperdir=$upper,workdir=$work" "$target" \
      >> "$LOG" 2>&1; then
    module_log "$BOOTSTRAP_STAGE" "overlay mounted: $target"
    OVERLAY_MOUNTED_THIS_RUN=1
    return 0
  fi
  module_log "$BOOTSTRAP_STAGE" "overlay FAILED: $target"
  return 1
}

# Without overlayfs, a new file needs a directory mirror before it can be
# bind-mounted. Keep existing SELinux labels from cp -a and relabel only the
# mirror root plus the new module file; recursive relabeling is too expensive
# for APatch's blocking boot stage.
bind_mirror() {
  local target="$1" sub="$2" file="$3"
  local mirror
  mirror=$(bind_mirror_path "$target")
  rm -rf "$mirror"
  mkdir -p "$mirror"
  if ! mount -t tmpfs tmpfs "$mirror" >> "$LOG" 2>&1; then
    module_log "$BOOTSTRAP_STAGE" "bind mirror tmpfs FAILED: $target"
    rm -rf "$mirror"
    return 1
  fi
  if ! cp -a "$target/." "$mirror/" >> "$LOG" 2>&1; then
    module_log "$BOOTSTRAP_STAGE" "bind mirror copy FAILED: $target"
    umount "$mirror" 2>>"$LOG" || true
    rm -rf "$mirror"
    return 1
  fi
  if ! cp "$MODDIR/system/$sub/$file" "$mirror/$file" >> "$LOG" 2>&1; then
    module_log "$BOOTSTRAP_STAGE" "bind mirror install FAILED: $file"
    umount "$mirror" 2>>"$LOG" || true
    rm -rf "$mirror"
    return 1
  fi
  chmod 644 "$mirror/$file"
  if ! chcon u:object_r:system_file:s0 "$mirror" "$mirror/$file" \
      >> "$LOG" 2>&1; then
    module_log "$BOOTSTRAP_STAGE" "bind mirror relabel FAILED: $target"
    umount "$mirror" 2>>"$LOG" || true
    rm -rf "$mirror"
    return 1
  fi
  if ! mount --bind "$mirror" "$target" >> "$LOG" 2>&1; then
    module_log "$BOOTSTRAP_STAGE" "bind mount FAILED: $target"
    umount "$mirror" 2>>"$LOG" || true
    rm -rf "$mirror"
    return 1
  fi
  module_log "$BOOTSTRAP_STAGE" "bind mirror mounted: $target"
  return 0
}

manager_file_present() {
  [ -f "$1" ]
}

cleanup_mounts() {
  if [ "${VINTF_MOUNTED_THIS_RUN:-0}" -eq 1 ]; then
    umount /system/etc/vintf/manifest 2>>"$LOG" || true
    umount "$(bind_mirror_path /system/etc/vintf/manifest)" 2>>"$LOG" || true
  fi
  if [ "${PERMISSIONS_MOUNTED_THIS_RUN:-0}" -eq 1 ]; then
    umount /system/etc/permissions 2>>"$LOG" || true
    umount "$(bind_mirror_path /system/etc/permissions)" 2>>"$LOG" || true
  fi
}

bootstrap_failed() {
  module_log "$BOOTSTRAP_STAGE" "bootstrap prerequisites failed; restoring properties and blocking services"
  cleanup_mounts
  restore_original_properties
  : > "$FAILED_MARKER"
  chmod 600 "$FAILED_MARKER"
  return 1
}

install_permission_feature() {
  local target=/system/etc/permissions
  local upper="$RUNTIME/permissions-upper"
  local work="$RUNTIME/permissions-work"
  local file=mock-telephony-features.xml
  PERMISSIONS_MOUNTED_THIS_RUN=0

  if manager_file_present "$target/$file"; then
    module_log "$BOOTSTRAP_STAGE" "feature already injected by the manager"
    PERMISSIONS_READY=1
  elif overlay_supported && overlay_mount "$target" "$upper" "$work"; then
    PERMISSIONS_MOUNTED_THIS_RUN=$OVERLAY_MOUNTED_THIS_RUN
    if cp "$MODDIR/system/etc/permissions/$file" "$target/$file" \
        && chmod 644 "$target/$file" \
        && chcon u:object_r:system_file:s0 "$target/$file"; then
      PERMISSIONS_READY=1
      module_log "$BOOTSTRAP_STAGE" "feature installed: $file"
    else
      module_log "$BOOTSTRAP_STAGE" "feature install FAILED: $file"
    fi
  elif ! overlay_supported && bind_mirror "$target" etc/permissions "$file"; then
    PERMISSIONS_MOUNTED_THIS_RUN=1
    PERMISSIONS_READY=1
  fi
}

install_vintf_fragment() {
  local target=/system/etc/vintf/manifest
  local upper="$RUNTIME/vintf-system-upper"
  local work="$RUNTIME/vintf-system-work"
  local file=mockmodem.radio.xml
  VINTF_MOUNTED_THIS_RUN=0

  if manager_file_present "$target/$file"; then
    module_log "$BOOTSTRAP_STAGE" "vintf fragment already injected by the manager"
    VINTF_READY=1
  elif overlay_supported && overlay_mount "$target" "$upper" "$work"; then
    VINTF_MOUNTED_THIS_RUN=$OVERLAY_MOUNTED_THIS_RUN
    if cp "$MODDIR/system/etc/vintf/manifest/$file" "$target/$file" \
        && chmod 644 "$target/$file" \
        && chcon u:object_r:system_file:s0 "$target/$file"; then
      VINTF_READY=1
      module_log "$BOOTSTRAP_STAGE" "vintf fragment installed: $file"
    else
      module_log "$BOOTSTRAP_STAGE" "vintf fragment install FAILED: $file"
    fi
  elif ! overlay_supported && bind_mirror "$target" etc/vintf/manifest "$file"; then
    VINTF_MOUNTED_THIS_RUN=1
    VINTF_READY=1
  fi
}

bootstrap_apply() {
  save_original_properties
  PERMISSIONS_READY=0
  VINTF_READY=0
  PERMISSIONS_MOUNTED_THIS_RUN=0
  VINTF_MOUNTED_THIS_RUN=0

  install_permission_feature
  install_vintf_fragment

  if [ "$PERMISSIONS_READY" -ne 1 ] || [ "$VINTF_READY" -ne 1 ]; then
    bootstrap_failed
    return 1
  fi

  if [ ! -x "$RESETPROP" ]; then
    module_log "$BOOTSTRAP_STAGE" "resetprop missing ($RESETPROP); cannot set module properties"
    bootstrap_failed
    return 1
  fi
  "$RESETPROP" -n ro.radio.noril false \
    || { module_log "$BOOTSTRAP_STAGE" "failed to set ro.radio.noril"; bootstrap_failed; return 1; }
  "$RESETPROP" -n persist.radio.allow_mock_modem true \
    || { module_log "$BOOTSTRAP_STAGE" "failed to enable mock modem property"; bootstrap_failed; return 1; }
  module_log "$BOOTSTRAP_STAGE" "done"
  return 0
}
