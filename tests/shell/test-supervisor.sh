#!/usr/bin/env bash
# Behavioral tests for module/mockmodem-supervisor.sh: self-healing loop.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

SUP() { echo "/data/adb/modules/mock_telephony/mockmodem-supervisor.sh"; }

case_uninstall_marker_exits() {
  seed_runtime .uninstalling ""
  harness_run mockmodem-supervisor.sh; local rc=$?
  [ "$rc" -eq 0 ] || { echo "  ASSERT: supervisor rc=$rc" >&2; return 1; }
  # Must not spawn a daemon.
  assert_not_exists "$SANDBOX/trace/app_process" || return 1
  return 0
}

case_restarts_with_backoff() {
  set_app_process_behavior exit
  harness_sh -c "timeout 2 /bin/sh /data/adb/modules/mock_telephony/mockmodem-supervisor.sh"; local rc=$?
  [ "$rc" -eq 124 ] || { echo "  ASSERT: expected timeout (124), got $rc" >&2; return 1; }
  local starts
  starts=$(wc -l < "$SANDBOX/trace/app_process")
  [ "$starts" -ge 3 ] || { echo "  ASSERT: expected >=3 daemon starts, got $starts" >&2; return 1; }
  assert_exists "$SANDBOX/data/adb/modules/mock_telephony/.runtime/supervisor.pid" || return 1
  return 0
}

case_backoff_doubles() {
  set_app_process_behavior exit
  harness_sh -c "timeout 2 /bin/sh /data/adb/modules/mock_telephony/mockmodem-supervisor.sh"; local rc=$?
  [ "$rc" -eq 124 ] || { echo "  ASSERT: expected timeout (124), got $rc" >&2; return 1; }
  # The sleep shim records each requested interval; a healthy loop doubles it.
  for interval in 1 2 4 8; do
    grep -qF "sleep $interval" "$SANDBOX/trace/sleep" \
      || { echo "  ASSERT: missing backoff interval $interval" >&2; return 1; }
  done
  return 0
}

case_adopts_running_daemon() {
  set_app_process_behavior exit
  harness_sh -c "timeout 2 /bin/sh -c '
    mkdir -p /data/adb/modules/mock_telephony/.runtime
    exec -a mockmodem /bin/sleep 3 &
    echo \$! > /data/adb/modules/mock_telephony/.runtime/mockmodem.pid
    exec /bin/sh /data/adb/modules/mock_telephony/mockmodem-supervisor.sh
  '"; local rc=$?
  # Adopt log is written on the first iteration; the run is bounded by timeout.
  assert_log_contains "adopting running mockmodem" || return 1
  return 0
}

run_case supervisor:uninstall-marker-exits case_uninstall_marker_exits
run_case supervisor:restarts-with-backoff case_restarts_with_backoff
run_case supervisor:backoff-doubles case_backoff_doubles
run_case supervisor:adopts-running-daemon case_adopts_running_daemon

summary
