#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"
init_runtime

PIDFILE="$RUNTIME/mockmodem.pid"
STOP_MARKER="$RUNTIME/.uninstalling"
BACKOFF=1

module_log supervisor "started pid $$"
# Self-register so the daemon watchdog can tell when a respawned supervisor has taken over.
echo $$ > "$RUNTIME/supervisor.pid"
chmod 600 "$RUNTIME/supervisor.pid"

daemon_alive() {
  process_matches "$(cat "$PIDFILE" 2>/dev/null)" mockmodem
}

while true; do
  [ -f "$STOP_MARKER" ] && exit 0

  if daemon_alive; then
    # A respawned supervisor may find the daemon that spawned it still running; 
    # adopt it instead of starting a second copy (two daemons would race to register the same HAL names).
    DAEMON_PID=$(cat "$PIDFILE" 2>/dev/null)
    module_log supervisor "adopting running mockmodem pid $DAEMON_PID"
    STARTED_AT=$(date +%s)
    while daemon_alive; do
      [ -f "$STOP_MARKER" ] && exit 0
      sleep 5
    done
    STOPPED_AT=$(date +%s)
    STATUS=1
  else
    STARTED_AT=$(date +%s)
    /system/bin/app_process \
      -Djava.class.path="$MODDIR/bin/mockmodem.jar" \
      /system/bin --nice-name=mockmodem \
      android.telephony.mockmodem.MockModemMain >> "$LOG" 2>&1 &
    CHILD=$!
    echo "$CHILD" > "$PIDFILE"
    chmod 600 "$PIDFILE"
    module_log supervisor "started mockmodem pid $CHILD"
    wait "$CHILD"
    STATUS=$?
    STOPPED_AT=$(date +%s)
    rm -f "$PIDFILE"
  fi

  [ -f "$STOP_MARKER" ] && exit 0

  if [ $((STOPPED_AT - STARTED_AT)) -ge 60 ]; then
    BACKOFF=1
  fi
  module_log supervisor "mockmodem exited status $STATUS; restart in ${BACKOFF}s"

  sleep "$BACKOFF"
  if [ "$BACKOFF" -lt 30 ]; then
    BACKOFF=$((BACKOFF * 2))
  fi
done
