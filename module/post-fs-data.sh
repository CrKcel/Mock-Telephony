#!/system/bin/sh
MODDIR=${0%/*}
BOOTSTRAP_STAGE=post-fs-data
. "$MODDIR/bootstrap.sh"

# APatch mounts module system trees after this stage. Capture the original
# property now, then perform injection and property activation from
# post-mount.sh after the manager's native overlay has settled.
bootstrap_prepare
if [ "${APATCH:-}" = true ]; then
  exit 0
fi
bootstrap_apply
