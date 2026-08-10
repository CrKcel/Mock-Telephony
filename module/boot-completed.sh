#!/system/bin/sh
#
# Boot-completed verification. Writes a report to the module-private log.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
init_runtime
{
  echo "=== boot-completed $(date) ==="
  echo "-- properties --"
  getprop ro.radio.noril
  getprop gsm.version.baseband
  echo "-- features --"
  pm list features 2>/dev/null | grep -i telephony || echo "NO telephony features"
  echo "-- phone service --"
  service check phone 2>&1
  echo "-- registered radio HALs --"
  service list 2>/dev/null | grep -iE "IRadio|radio" || echo "none listed"
  echo "-- telephony registry --"
  dumpsys telephony.registry 2>/dev/null | grep -E "mDefaultPhoneId|mDefaultSubId|mPhoneCapability" || true
  echo "-- mock modem service process --"
  PID=$(cat "$RUNTIME/mockmodem.pid" 2>/dev/null)
  if process_matches "$PID" mockmodem; then
    echo "$PID"
  else
    echo "mockmodem not running"
  fi
} >> "$LOG" 2>&1
