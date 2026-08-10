#!/usr/bin/env bash
# Behavioral tests for module/common.sh shared helpers: log rotation.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

RT() { echo "$SANDBOX/data/adb/modules/mock_telephony/.runtime"; }

case_log_rotates() {
  local rt
  rt="$(RT)"
  mkdir -p "$rt"
  # Seed an oversized log; init_runtime must rotate it before appending.
  head -c 600000 /dev/zero | tr '\0' x > "$rt/mock_telephony.log"
  harness_run boot-completed.sh || return 1
  assert_exists "$rt/mock_telephony.log.1" || return 1
  local rotated new_size
  rotated=$(wc -c < "$rt/mock_telephony.log.1")
  new_size=$(wc -c < "$rt/mock_telephony.log")
  [ "$rotated" -ge 600000 ] \
    || { echo "  ASSERT: rotated log is only $rotated bytes" >&2; return 1; }
  [ "$new_size" -lt 524288 ] \
    || { echo "  ASSERT: new log is $new_size bytes" >&2; return 1; }
  return 0
}

case_log_kept_under_threshold() {
  # A small log is left untouched (no .log.1 rotation happens).
  local rt
  rt="$(RT)"
  mkdir -p "$rt"
  printf 'small log\n' > "$rt/mock_telephony.log"
  harness_run boot-completed.sh || return 1
  assert_not_exists "$rt/mock_telephony.log.1" || return 1
  assert_file_contains "$rt/mock_telephony.log" "small log" || return 1
  return 0
}

run_case common:log-rotates case_log_rotates
run_case common:log-under-threshold case_log_kept_under_threshold

summary
