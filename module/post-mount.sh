#!/system/bin/sh
MODDIR=${0%/*}
BOOTSTRAP_STAGE=post-mount
. "$MODDIR/bootstrap.sh"

# Magisk and older KernelSU releases do not use this stage. APatch invokes it
# after its native module overlay/metamodule mount has completed.
if [ "${APATCH:-}" != true ]; then
  exit 0
fi
bootstrap_apply
